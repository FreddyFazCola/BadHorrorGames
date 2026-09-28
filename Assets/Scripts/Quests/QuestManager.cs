using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Events;

namespace Arcaneum
{
    [System.Serializable] public class QuestStringEvent : UnityEvent<string> { }

    /// <summary>
    /// Data-driven quest state machine, one per game session. Missions are authored as
    /// QuestDefinition assets assigned in allQuests -- see Docs/QUEST_OUTLINE.md for the
    /// 14-mission main quest this is designed to drive.
    /// </summary>
    public class QuestManager : MonoBehaviour
    {
        public static QuestManager Instance { get; private set; }

        [Tooltip("Every quest in the game, assigned in the Inspector.")]
        public List<QuestDefinition> allQuests = new List<QuestDefinition>();

        public QuestStringEvent onQuestStarted;
        public QuestStringEvent onQuestCompleted;

        private readonly Dictionary<string, QuestDefinition> questLookup = new Dictionary<string, QuestDefinition>();
        private readonly Dictionary<string, ActiveQuestState> activeQuests = new Dictionary<string, ActiveQuestState>();
        private readonly HashSet<string> completedQuestIds = new HashSet<string>();

        private void Awake()
        {
            if (Instance != null && Instance != this) { Destroy(gameObject); return; }
            Instance = this;

            foreach (var quest in allQuests)
                if (quest != null && !string.IsNullOrEmpty(quest.questId))
                    questLookup[quest.questId] = quest;
        }

        public bool StartQuest(string questId)
        {
            if (activeQuests.ContainsKey(questId) || completedQuestIds.Contains(questId)) return false;
            if (!questLookup.TryGetValue(questId, out var quest))
            {
                Debug.LogWarning($"QuestManager.StartQuest: no quest found with id '{questId}'.");
                return false;
            }
            if (!string.IsNullOrEmpty(quest.prerequisiteQuestId) && !completedQuestIds.Contains(quest.prerequisiteQuestId))
                return false;

            activeQuests[questId] = new ActiveQuestState { questId = questId, currentStageIndex = 0 };
            onQuestStarted?.Invoke(questId);
            return true;
        }

        /// <summary>Call when a trigger/dialogue choice/kill-count/etc satisfies one objective of the quest's current stage.</summary>
        public void CompleteObjective(string questId, string objectiveId)
        {
            if (!activeQuests.TryGetValue(questId, out var state) || state.isCompleted) return;
            if (!questLookup.TryGetValue(questId, out var quest)) return;

            if (!state.completedObjectiveIds.Contains(objectiveId))
                state.completedObjectiveIds.Add(objectiveId);

            AdvanceStageIfReady(quest, state);
        }

        private void AdvanceStageIfReady(QuestDefinition quest, ActiveQuestState state)
        {
            if (state.currentStageIndex >= quest.stages.Count) return;
            var stage = quest.stages[state.currentStageIndex];

            foreach (var required in stage.requiredObjectiveIds)
                if (!state.completedObjectiveIds.Contains(required))
                    return; // still waiting on at least one objective in this stage

            state.currentStageIndex++;
            if (state.currentStageIndex >= quest.stages.Count)
            {
                state.isCompleted = true;
                completedQuestIds.Add(quest.questId);
                onQuestCompleted?.Invoke(quest.questId);
            }
        }

        public bool IsQuestActive(string questId) => activeQuests.TryGetValue(questId, out var s) && !s.isCompleted;
        public bool IsQuestCompleted(string questId) => completedQuestIds.Contains(questId);

        public string GetCurrentObjectiveText(string questId)
        {
            if (!activeQuests.TryGetValue(questId, out var state)) return string.Empty;
            if (!questLookup.TryGetValue(questId, out var quest)) return string.Empty;
            if (state.currentStageIndex >= quest.stages.Count) return string.Empty;
            return quest.stages[state.currentStageIndex].objectiveText;
        }

        public List<ActiveQuestState> GetActiveQuestStates() => new List<ActiveQuestState>(activeQuests.Values);
        public List<string> GetCompletedQuestIds() => new List<string>(completedQuestIds);

        /// <summary>Restores progress from a loaded SaveData.</summary>
        public void RestoreState(List<ActiveQuestState> savedActive, List<string> savedCompleted)
        {
            activeQuests.Clear();
            foreach (var s in savedActive) activeQuests[s.questId] = s;
            completedQuestIds.Clear();
            foreach (var id in savedCompleted) completedQuestIds.Add(id);
        }
    }
}
