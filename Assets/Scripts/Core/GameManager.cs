using UnityEngine;

namespace Arcaneum
{
    /// <summary>Top-level orchestration: starts the prologue quest on a new game.</summary>
    public class GameManager : MonoBehaviour
    {
        [Tooltip("Main-quest id to auto-start on a brand-new game (see Docs/QUEST_OUTLINE.md).")]
        public string prologueQuestId = "Q01_LateAdmission";

        private void Start()
        {
            if (SaveLoadManager.SaveExists())
            {
                // TODO: load the save and call QuestManager.Instance.RestoreState(...) /
                // SpellCasting.LearnSpell(...) / FactionReputation.ChangeReputation(...) instead
                // of starting the prologue fresh. Left as a hook until a main menu / load-slot
                // UI exists.
            }
            else if (QuestManager.Instance != null)
            {
                QuestManager.Instance.StartQuest(prologueQuestId);
            }
        }
    }
}
