using UnityEngine;

namespace Arcaneum
{
    /// <summary>
    /// Base enemy AI: patrol between waypoints, chase the player within range, attack in melee
    /// range. Movement is plain Transform-based (no NavMeshAgent) so this has zero dependency on
    /// whether the "AI Navigation" package is installed -- swap in NavMeshAgent later once a
    /// NavMesh is baked, for proper pathfinding/obstacle avoidance around level geometry.
    /// Implements IDamageable so SpellProjectile (see Assets/Scripts/Spells) can damage it.
    /// </summary>
    public class EnemyController : MonoBehaviour, IDamageable
    {
        private enum State { Patrol, Chase, Attack }

        [Header("Health")]
        public float maxHealth = 50f;
        [SerializeField] private float currentHealth;

        [Header("Movement")]
        public Transform[] patrolPoints;
        public float patrolSpeed = 2f;
        public float chaseSpeed = 4f;
        public float waypointTolerance = 0.3f;

        [Header("Detection & Combat")]
        public float chaseRange = 8f;
        public float attackRange = 1.6f;
        public float attackDamage = 10f;
        public float attackCooldown = 1.5f;

        [Tooltip("The player must have this tag (Unity's built-in 'Player' tag, set in the Inspector).")]
        public string playerTag = "Player";

        private Transform player;
        private State state = State.Patrol;
        private int patrolIndex;
        private float attackTimer;
        private bool isDead;

        private void Awake()
        {
            currentHealth = maxHealth;
            var playerObj = GameObject.FindWithTag(playerTag);
            if (playerObj != null) player = playerObj.transform;
        }

        private void Update()
        {
            if (isDead || player == null) return;

            float distanceToPlayer = Vector3.Distance(transform.position, player.position);
            state = distanceToPlayer <= attackRange ? State.Attack
                   : distanceToPlayer <= chaseRange ? State.Chase
                   : State.Patrol;

            switch (state)
            {
                case State.Patrol: DoPatrol(); break;
                case State.Chase: DoChase(); break;
                case State.Attack: DoAttack(); break;
            }

            if (attackTimer > 0f) attackTimer -= Time.deltaTime;
        }

        private void DoPatrol()
        {
            if (patrolPoints == null || patrolPoints.Length == 0) return;

            Transform target = patrolPoints[patrolIndex];
            MoveTowards(target.position, patrolSpeed);

            if (Vector3.Distance(transform.position, target.position) <= waypointTolerance)
                patrolIndex = (patrolIndex + 1) % patrolPoints.Length;
        }

        private void DoChase()
        {
            MoveTowards(player.position, chaseSpeed);
        }

        private void DoAttack()
        {
            FaceTowards(player.position);
            if (attackTimer > 0f) return;

            attackTimer = attackCooldown;
            var damageable = player.GetComponentInParent<IDamageable>();
            damageable?.ApplyDamage(attackDamage);
        }

        private void MoveTowards(Vector3 targetPosition, float speed)
        {
            Vector3 direction = targetPosition - transform.position;
            direction.y = 0f;
            if (direction.sqrMagnitude < 0.0001f) return;

            transform.position += direction.normalized * speed * Time.deltaTime;
            FaceTowards(targetPosition);
        }

        private void FaceTowards(Vector3 targetPosition)
        {
            Vector3 direction = targetPosition - transform.position;
            direction.y = 0f;
            if (direction.sqrMagnitude < 0.0001f) return;

            transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(direction), 10f * Time.deltaTime);
        }

        public void ApplyDamage(float amount)
        {
            if (isDead || amount <= 0f) return;

            currentHealth = Mathf.Max(0f, currentHealth - amount);
            if (currentHealth <= 0f)
            {
                isDead = true;
                // Swap this for a death animation/ragdoll/loot-drop hook once art exists.
                Destroy(gameObject);
            }
        }
    }
}
