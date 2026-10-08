using UnityEngine;
using UnityEngine.Events;

namespace Arcaneum
{
    [System.Serializable] public class ShardEvent : UnityEvent<string> { }

    /// <summary>
    /// One of the ~40 Sundering Shard lore collectibles (see Docs/WORLD_AND_FACTIONS.md).
    /// Attach to a trigger-collider prop; on pickup it unlocks a world-history log entry by id
    /// and removes itself. Collected ids live on the GameManager/save flow, not here --
    /// this component only reports the pickup event.
    /// </summary>
    public class SunderingShard : MonoBehaviour
    {
        [Tooltip("Unique id for this shard's lore entry, e.g. 'Shard_14_FoundersPact'.")]
        public string shardId;

        public static ShardEvent OnAnyShardCollected = new ShardEvent();
        public UnityEvent onCollected;

        private void OnTriggerEnter(Collider other)
        {
            if (!other.CompareTag("Player")) return;

            OnAnyShardCollected.Invoke(shardId);
            onCollected?.Invoke();
            Destroy(gameObject);
        }
    }
}
