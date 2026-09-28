using System.Collections.Generic;
using UnityEngine;

namespace Arcaneum
{
    /// <summary>
    /// One quest's full definition (see Docs/QUEST_OUTLINE.md). Create one asset per mission
    /// via Assets > Create > Arcaneum > Quest Definition -- adding/editing missions is an
    /// asset edit, not a code change.
    /// </summary>
    [CreateAssetMenu(fileName = "Quest_", menuName = "Arcaneum/Quest Definition")]
    public class QuestDefinition : ScriptableObject
    {
        [Tooltip("Unique id, e.g. Q01_LateAdmission -- referenced by GameManager/QuestManager calls.")]
        public string questId;
        public string displayName;
        public int actNumber = 1;
        public int missionNumber = 1;
        public bool isMainQuest = true;
        public List<QuestStage> stages = new List<QuestStage>();

        [Tooltip("questId of a quest that must be completed first; empty = unrestricted.")]
        public string prerequisiteQuestId;
    }
}
