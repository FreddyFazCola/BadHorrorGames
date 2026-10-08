using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Events;

namespace Arcaneum
{
    [System.Serializable] public class SpellEvent : UnityEvent<SpellDefinition> { }
    [System.Serializable] public class ManaEvent : UnityEvent<float> { }

    /// <summary>
    /// Owns mana, cooldowns, known spells, and cast resolution for whatever GameObject it's
    /// attached to (the player, and potentially spellcasting NPC enemies later).
    /// </summary>
    public class SpellCasting : MonoBehaviour
    {
        [Header("Mana")]
        public float maxMana = 100f;
        public float manaRegenPerSecond = 5f;
        [SerializeField] private float currentMana;
        public float CurrentMana => currentMana;

        [Header("Progression")]
        [Tooltip("Highest story-progression tier unlocked so far; gates LearnSpell (see Docs/SPELL_LIST.md).")]
        [SerializeField] private int currentTier = 1;
        public int CurrentTier => currentTier;

        [Header("Cast point")]
        [Tooltip("Where projectiles/effects spawn from -- assign a hand/wand transform once a rigged model is in place. Defaults to this transform.")]
        public Transform castPoint;

        public SpellEvent onSpellCast;
        public ManaEvent onManaChanged;
        public SpellEvent onSpellLearned;

        private readonly List<SpellDefinition> knownSpells = new List<SpellDefinition>();
        private readonly Dictionary<SpellDefinition, float> cooldownRemaining = new Dictionary<SpellDefinition, float>();
        private Animator animator;

        public IReadOnlyList<SpellDefinition> KnownSpells => knownSpells;

        private void Awake()
        {
            currentMana = maxMana;
            animator = GetComponent<Animator>();
            if (castPoint == null) castPoint = transform;
        }

        private void Update()
        {
            if (currentMana < maxMana)
            {
                currentMana = Mathf.Min(maxMana, currentMana + manaRegenPerSecond * Time.deltaTime);
                onManaChanged?.Invoke(maxMana > 0f ? currentMana / maxMana : 0f);
            }

            if (cooldownRemaining.Count == 0) return;
            var keys = new List<SpellDefinition>(cooldownRemaining.Keys);
            foreach (var spell in keys)
            {
                if (cooldownRemaining[spell] > 0f)
                    cooldownRemaining[spell] = Mathf.Max(0f, cooldownRemaining[spell] - Time.deltaTime);
            }
        }

        public bool IsSpellKnown(SpellDefinition spell) => spell != null && knownSpells.Contains(spell);

        public bool IsSpellOnCooldown(SpellDefinition spell) =>
            spell != null && cooldownRemaining.TryGetValue(spell, out var remaining) && remaining > 0f;

        /// <summary>Instant mana restore (a Draught, a shrine, etc.) -- separate from the passive per-second regen.</summary>
        public void RestoreMana(float amount)
        {
            if (amount <= 0f) return;
            currentMana = Mathf.Min(maxMana, currentMana + amount);
            onManaChanged?.Invoke(maxMana > 0f ? currentMana / maxMana : 0f);
        }

        /// <summary>Called by QuestManager (via a listener) when a mission teaches a new spell.</summary>
        public bool LearnSpell(SpellDefinition spell)
        {
            if (spell == null || spell.requiredTier > currentTier || IsSpellKnown(spell)) return false;
            knownSpells.Add(spell);
            cooldownRemaining[spell] = 0f;
            onSpellLearned?.Invoke(spell);
            return true;
        }

        public void SetCurrentTier(int newTier) => currentTier = Mathf.Max(currentTier, newTier);

        public SpellCastResult TryCastSpell(SpellDefinition spell)
        {
            if (!IsSpellKnown(spell)) return SpellCastResult.NotLearned;
            if (IsSpellOnCooldown(spell)) return SpellCastResult.OnCooldown;
            if (currentMana < spell.manaCost) return SpellCastResult.InsufficientMana;

            currentMana -= spell.manaCost;
            cooldownRemaining[spell] = spell.cooldownSeconds;
            onManaChanged?.Invoke(maxMana > 0f ? currentMana / maxMana : 0f);

            ApplyEffect(spell);
            onSpellCast?.Invoke(spell);
            return SpellCastResult.Success;
        }

        private void ApplyEffect(SpellDefinition spell)
        {
            if (animator != null && !string.IsNullOrEmpty(spell.castAnimationTrigger))
                animator.SetTrigger(spell.castAnimationTrigger);

            if (spell.castEffectPrefab != null)
                Instantiate(spell.castEffectPrefab, castPoint.position, castPoint.rotation);

            if (spell.castSound != null)
                AudioSource.PlayClipAtPoint(spell.castSound, castPoint.position);

            if (spell.projectilePrefab != null)
            {
                var projectile = Instantiate(spell.projectilePrefab, castPoint.position, castPoint.rotation);
                projectile.Initialize(spell, gameObject);
            }
            // Spells without a projectilePrefab (self/instant effects like a buff Warding)
            // are expected to be handled by dedicated buff logic as those systems are built out;
            // this is the single point to extend when that lands.
        }
    }
}
