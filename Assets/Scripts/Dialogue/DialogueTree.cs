using System.Collections.Generic;
using UnityEngine;

namespace Arcaneum
{
    /// <summary>A full branching conversation, authored as a list of DialogueLine entries keyed by lineId.</summary>
    [CreateAssetMenu(fileName = "Dialogue_", menuName = "Arcaneum/Dialogue Tree")]
    public class DialogueTree : ScriptableObject
    {
        public string startLineId;
        public List<DialogueLine> lines = new List<DialogueLine>();

        private Dictionary<string, DialogueLine> lookup;

        public DialogueLine FindLine(string lineId)
        {
            if (string.IsNullOrEmpty(lineId)) return null;
            if (lookup == null)
            {
                lookup = new Dictionary<string, DialogueLine>();
                foreach (var line in lines)
                    if (!string.IsNullOrEmpty(line.lineId))
                        lookup[line.lineId] = line;
            }
            lookup.TryGetValue(lineId, out var found);
            return found;
        }
    }
}
