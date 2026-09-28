using System;
using System.Collections.Generic;
using UnityEngine;

namespace Arcaneum
{
    /// <summary>One step within a quest. See Docs/QUEST_OUTLINE.md for the authored 14-mission main quest.</summary>
    [Serializable]
    public class QuestStage
    {
        public string stageId;
        [TextArea] public string objectiveText;

        [Tooltip("All of these objective ids must be completed (via QuestManager.CompleteObjective) before the stage advances.")]
        public List<string> requiredObjectiveIds = new List<string>();

        [Tooltip("SpellDefinition.spellId to grant on reaching this stage; empty = no spell granted.")]
        public string grantsSpellId;
    }

    /// <summary>Runtime progress for one in-progress or completed quest; this is what gets serialized into SaveData.</summary>
    [Serializable]
    public class ActiveQuestState
    {
        public string questId;
        public int currentStageIndex;
        public List<string> completedObjectiveIds = new List<string>();
        public bool isCompleted;
    }
}
