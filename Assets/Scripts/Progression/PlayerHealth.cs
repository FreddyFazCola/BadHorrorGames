using UnityEngine;
using UnityEngine.Events;

namespace Arcaneum
{
    [System.Serializable] public class HealthEvent : UnityEvent<float> { }

    /// <summary>Player-side damage sink. Enemies (see EnemyController) and hazards deal damage via IDamageable.</summary>
    public class PlayerHealth : MonoBehaviour, IDamageable
    {
        public float maxHealth = 100f;
        [SerializeField] private float currentHealth;
        public float CurrentHealth => currentHealth;

        /// <summary>Fires with the new health fraction (0-1) any time health changes.</summary>
        public HealthEvent onHealthChanged;
        public UnityEvent onDied;

        private bool isDead;

        private void Awake()
        {
            currentHealth = maxHealth;
        }

        public void ApplyDamage(float amount)
        {
            if (isDead || amount <= 0f) return;

            currentHealth = Mathf.Max(0f, currentHealth - amount);
            onHealthChanged?.Invoke(maxHealth > 0f ? currentHealth / maxHealth : 0f);

            if (currentHealth <= 0f)
            {
                isDead = true;
                onDied?.Invoke();
            }
        }

        public void Heal(float amount)
        {
            if (isDead || amount <= 0f) return;
            currentHealth = Mathf.Min(maxHealth, currentHealth + amount);
            onHealthChanged?.Invoke(maxHealth > 0f ? currentHealth / maxHealth : 0f);
        }
    }
}
