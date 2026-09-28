using System;
using System.Collections.Generic;
using UnityEngine;

namespace Arcaneum
{
    [Serializable]
    public class DialogueChoice
    {
        public string choiceText;

        [Tooltip("Id of the next DialogueLine to jump to; empty ends the conversation.")]
        public string nextLineId;

        [Tooltip("Optional: completes this objective on the given quest when picked (QuestManager.CompleteObjective).")]
        public string questIdToUpdate;
        public string objectiveIdToComplete;

        [Tooltip("Optional: nudges the player's Order standing (ArcaneumOrder in FactionReputation.cs).")]
        public bool affectsFactionReputation;
        public ArcaneumOrder factionOrder;
        public int reputationDelta;
    }

    /// <summary>One line of a conversation, identified by lineId within a DialogueTree.</summary>
    [Serializable]
    public class DialogueLine
    {
        public string lineId;
        public string speakerName;
        [TextArea] public string lineText;

        [Tooltip("Empty = a single 'Continue' advances via nextLineIdIfNoChoices; non-empty = branching choices shown instead.")]
        public List<DialogueChoice> choices = new List<DialogueChoice>();
        public string nextLineIdIfNoChoices;
    }
}
