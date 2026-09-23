#include "DialogueComponent.h"
#include "../Quests/QuestManagerSubsystem.h"
#include "Engine/World.h"

const FDialogueLine* UDialogueComponent::FindLine(FName LineID) const
{
	if (!DialogueTable || LineID.IsNone())
	{
		return nullptr;
	}
	return DialogueTable->FindRow<FDialogueLine>(LineID, TEXT("UDialogueComponent::FindLine"));
}

void UDialogueComponent::StartDialogue()
{
	GoToLine(StartLineID);
}

void UDialogueComponent::GoToLine(FName LineID)
{
	const FDialogueLine* Line = FindLine(LineID);
	if (!Line)
	{
		CurrentLineID = NAME_None;
		OnDialogueEnded.Broadcast();
		return;
	}

	CurrentLineID = LineID;
	OnDialogueLineChanged.Broadcast(*Line);
}

void UDialogueComponent::SelectChoice(int32 ChoiceIndex)
{
	const FDialogueLine* Line = FindLine(CurrentLineID);
	if (!Line || !Line->Choices.IsValidIndex(ChoiceIndex))
	{
		return;
	}

	const FDialogueChoice& Choice = Line->Choices[ChoiceIndex];

	if (!Choice.QuestIDToUpdate.IsNone() && !Choice.ObjectiveIDToComplete.IsNone())
	{
		if (UWorld* World = GetWorld())
		{
			if (UGameInstance* GameInstance = World->GetGameInstance())
			{
				if (UQuestManagerSubsystem* QuestManager = GameInstance->GetSubsystem<UQuestManagerSubsystem>())
				{
					QuestManager->CompleteObjective(Choice.QuestIDToUpdate, Choice.ObjectiveIDToComplete);
				}
			}
		}
	}

	// Choice.bAffectsFactionReputation is intentionally not applied here: this component
	// lives on the NPC, and reaching into the player pawn's UFactionReputationComponent
	// from here would couple dialogue data to a specific pawn class. Have the controller
	// (or a dedicated dialogue-UI glue class) listen for choice selection and apply the
	// reputation delta to the player instead.

	GoToLine(Choice.NextLineID);
}

void UDialogueComponent::AdvanceWithNoChoice()
{
	const FDialogueLine* Line = FindLine(CurrentLineID);
	if (!Line)
	{
		return;
	}
	GoToLine(Line->NextLineIDIfNoChoices);
}
