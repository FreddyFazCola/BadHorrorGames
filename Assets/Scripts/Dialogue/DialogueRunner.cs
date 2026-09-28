using UnityEngine;
using UnityEngine.Events;

namespace Arcaneum
{
    [System.Serializable] public class DialogueLineEvent : UnityEvent<DialogueLine> { }

    /// <summary>
    /// Attach to an NPC GameObject to give it a branching conversation. A UI script binds to
    /// onLineChanged/onDialogueEnded and calls SelectChoice/AdvanceWithNoChoice from player input.
    /// </summary>
    public class DialogueRunner : MonoBehaviour
    {
        public DialogueTree dialogueTree;

        public DialogueLineEvent onLineChanged;
        public UnityEvent onDialogueEnded;

        private string currentLineId;
        public bool IsInConversation => !string.IsNullOrEmpty(currentLineId);

        public void StartDialogue() => GoToLine(dialogueTree != null ? dialogueTree.startLineId : null);

        private void GoToLine(string lineId)
        {
            var line = dialogueTree != null ? dialogueTree.FindLine(lineId) : null;
            if (line == null)
            {
                currentLineId = null;
                onDialogueEnded?.Invoke();
                return;
            }
            currentLineId = lineId;
            onLineChanged?.Invoke(line);
        }

        public void SelectChoice(int choiceIndex)
        {
            var line = dialogueTree != null ? dialogueTree.FindLine(currentLineId) : null;
            if (line == null || choiceIndex < 0 || choiceIndex >= line.choices.Count) return;

            var choice = line.choices[choiceIndex];

            if (!string.IsNullOrEmpty(choice.questIdToUpdate) && !string.IsNullOrEmpty(choice.objectiveIdToComplete) && QuestManager.Instance != null)
                QuestManager.Instance.CompleteObjective(choice.questIdToUpdate, choice.objectiveIdToComplete);

            // choice.affectsFactionReputation is intentionally not applied here: this component
            // lives on the NPC. Have your dialogue UI (which already has a player reference)
            // read the choice and call the player's FactionReputation.ChangeReputation instead
            // of reaching into the player from here.

            GoToLine(choice.nextLineId);
        }

        public void AdvanceWithNoChoice()
        {
            var line = dialogueTree != null ? dialogueTree.FindLine(currentLineId) : null;
            if (line == null) return;
            GoToLine(line.nextLineIdIfNoChoices);
        }
    }
}
