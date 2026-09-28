using UnityEngine;
using UnityEngine.Events;

namespace Arcaneum
{
    /// <summary>
    /// A trial-of-first-spark style target (see Docs/QUEST_OUTLINE.md mission 1 and the
    /// browser prototype it mirrors). Bind onStruck in the Inspector to a light/particle
    /// flash and an animation once art is in place.
    /// </summary>
    public class PracticeWard : MonoBehaviour, IDamageable
    {
        public UnityEvent onStruck;
        public bool Struck { get; private set; }

        public void ApplyDamage(float amount)
        {
            if (Struck) return;
            Struck = true;
            onStruck?.Invoke();
        }

        public void ResetWard() => Struck = false;
    }
}
