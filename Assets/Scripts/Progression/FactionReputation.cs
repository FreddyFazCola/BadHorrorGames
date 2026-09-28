using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Events;

namespace Arcaneum
{
    /// <summary>The four Orders (house-equivalent) -- see Docs/WORLD_AND_FACTIONS.md.</summary>
    public enum ArcaneumOrder { Ember, Deep, Root, Gale }

    [System.Serializable] public class ReputationEvent : UnityEvent<ArcaneumOrder, int> { }

    /// <summary>
    /// Tracks the player's standing with each of the four Orders. Nudged by dialogue choices
    /// and Order loyalty questline outcomes; read by the multi-slide epilogue at the end of
    /// the main quest (Docs/QUEST_OUTLINE.md, mission 14).
    /// </summary>
    public class FactionReputation : MonoBehaviour
    {
        public ReputationEvent onReputationChanged;

        private readonly Dictionary<ArcaneumOrder, int> reputation = new Dictionary<ArcaneumOrder, int>
        {
            { ArcaneumOrder.Ember, 0 }, { ArcaneumOrder.Deep, 0 }, { ArcaneumOrder.Root, 0 }, { ArcaneumOrder.Gale, 0 }
        };

        public ArcaneumOrder HomeOrder { get; private set; } = ArcaneumOrder.Ember;
        private bool homeOrderSet;

        public void ChangeReputation(ArcaneumOrder order, int delta)
        {
            reputation[order] = reputation.TryGetValue(order, out var v) ? v + delta : delta;
            onReputationChanged?.Invoke(order, reputation[order]);
        }

        public int GetReputation(ArcaneumOrder order) => reputation.TryGetValue(order, out var v) ? v : 0;

        public ArcaneumOrder GetHighestReputationOrder()
        {
            var best = ArcaneumOrder.Ember;
            int bestValue = int.MinValue;
            foreach (var pair in reputation)
                if (pair.Value > bestValue) { bestValue = pair.Value; best = pair.Key; }
            return best;
        }

        /// <summary>Set once at Sorting (Docs/QUEST_OUTLINE.md mission 2, "The Trial of Four"); grants a standing head start.</summary>
        public void SetHomeOrder(ArcaneumOrder order)
        {
            if (homeOrderSet) return;
            HomeOrder = order;
            homeOrderSet = true;
            ChangeReputation(order, 10);
        }

        public IReadOnlyDictionary<ArcaneumOrder, int> AllReputation => reputation;
    }
}
