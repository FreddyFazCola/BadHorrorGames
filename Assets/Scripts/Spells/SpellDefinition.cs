using UnityEngine;

namespace Arcaneum
{
    /// <summary>
    /// Data-driven definition of a single spell (see Docs/SPELL_LIST.md for the full roster).
    /// Create one asset per spell via Assets > Create > Arcaneum > Spell Definition --
    /// no code changes needed to add a spell.
    /// </summary>
    [CreateAssetMenu(fileName = "Spell_", menuName = "Arcaneum/Spell Definition")]
    public class SpellDefinition : ScriptableObject
    {
        [Header("Identity")]
        public string spellId;
        public string displayName;
        [TextArea] public string description;
        public SpellCategory category = SpellCategory.Cantrip;

        [Header("Progression (see Docs/SPELL_LIST.md)")]
        [Range(1, 5)] public int requiredTier = 1;

        [Header("Cost")]
        public float manaCost = 10f;
        public float cooldownSeconds = 5f;

        [Header("Effect")]
        public float damageAmount = 0f;
        [Tooltip("Leave null for an instant/self effect resolved directly by SpellCasting instead of a projectile.")]
        public SpellProjectile projectilePrefab;

        [Header("Presentation (assign once art/animation packs are imported)")]
        public string castAnimationTrigger = "Cast";
        public GameObject castEffectPrefab;
        public AudioClip castSound;
    }
}
