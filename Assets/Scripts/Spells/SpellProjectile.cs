using UnityEngine;

namespace Arcaneum
{
    /// <summary>
    /// Base behaviour for a spawned spell projectile prefab (Emberburst, Tempest Lance, etc).
    /// Movement is done manually in Update rather than via Rigidbody velocity so this doesn't
    /// depend on a specific Unity version's Rigidbody API. Requires a trigger Collider on the
    /// prefab; the Rigidbody is kept kinematic purely so OnTriggerEnter fires reliably.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    public class SpellProjectile : MonoBehaviour
    {
        public float speed = 16f;
        public float lifeSeconds = 2.5f;

        private SpellDefinition sourceSpell;
        private GameObject caster;

        public void Initialize(SpellDefinition spell, GameObject owner)
        {
            sourceSpell = spell;
            caster = owner;
        }

        private void Awake()
        {
            var body = GetComponent<Rigidbody>();
            body.isKinematic = true;
            body.useGravity = false;
        }

        private void Start()
        {
            Destroy(gameObject, lifeSeconds);
        }

        private void Update()
        {
            transform.Translate(Vector3.forward * speed * Time.deltaTime, Space.Self);
        }

        private void OnTriggerEnter(Collider other)
        {
            if (caster != null && other.transform.IsChildOf(caster.transform)) return;

            if (sourceSpell != null && sourceSpell.damageAmount > 0f)
            {
                var damageable = other.GetComponentInParent<IDamageable>();
                damageable?.ApplyDamage(sourceSpell.damageAmount);
            }

            if (sourceSpell != null && sourceSpell.castEffectPrefab != null)
                Instantiate(sourceSpell.castEffectPrefab, transform.position, Quaternion.LookRotation(-transform.forward));

            Destroy(gameObject);
        }
    }
}
