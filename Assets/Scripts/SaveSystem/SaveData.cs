using System;
using System.Collections.Generic;

namespace Arcaneum
{
    [Serializable]
    public class SerializableQuestState
    {
        public string questId;
        public int currentStageIndex;
        public List<string> completedObjectiveIds = new List<string>();
        public bool isCompleted;
    }

    [Serializable]
    public class SerializableReputation
    {
        public ArcaneumOrder order;
        public int value;
    }

    /// <summary>
    /// Full save-file payload, written/read as JSON by SaveLoadManager. A save/load flow
    /// (not yet wired to a menu) is responsible for populating this from QuestManager/
    /// SpellCasting/FactionReputation on save, and restoring them on load.
    /// </summary>
    [Serializable]
    public class SaveData
    {
        public string slotDisplayName;
        public string saveTimestamp;
        public string currentSceneName;
        public float playerX, playerY, playerZ;
        public float playerRotationY;

        public List<string> unlockedSpellIds = new List<string>();
        public int currentSpellTier = 1;

        public List<SerializableQuestState> activeQuestStates = new List<SerializableQuestState>();
        public List<string> completedQuestIds = new List<string>();

        public List<SerializableReputation> factionReputation = new List<SerializableReputation>();
        public ArcaneumOrder homeOrder;
    }
}
