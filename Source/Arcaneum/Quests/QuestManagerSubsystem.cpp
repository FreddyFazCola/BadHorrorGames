#include "QuestManagerSubsystem.h"

void UQuestManagerSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
}

const FQuestDefinitionRow* UQuestManagerSubsystem::FindQuestRow(FName QuestID) const
{
	if (!QuestDataTable)
	{
		return nullptr;
	}
	return QuestDataTable->FindRow<FQuestDefinitionRow>(QuestID, TEXT("UQuestManagerSubsystem::FindQuestRow"));
}

bool UQuestManagerSubsystem::StartQuest(FName QuestID)
{
	if (ActiveQuests.Contains(QuestID) || CompletedQuestIDs.Contains(QuestID))
	{
		return false;
	}

	const FQuestDefinitionRow* Row = FindQuestRow(QuestID);
	if (!Row)
	{
		UE_LOG(LogTemp, Warning, TEXT("UQuestManagerSubsystem::StartQuest - no quest row found for %s"), *QuestID.ToString());
		return false;
	}

	if (!Row->PrerequisiteQuestID.IsNone() && !CompletedQuestIDs.Contains(Row->PrerequisiteQuestID))
	{
		return false;
	}

	FActiveQuestState NewState;
	NewState.QuestID = QuestID;
	NewState.CurrentStageIndex = 0;
	ActiveQuests.Add(QuestID, NewState);

	OnQuestStarted.Broadcast(QuestID);
	return true;
}

void UQuestManagerSubsystem::CompleteObjective(FName QuestID, FName ObjectiveID)
{
	FActiveQuestState* State = ActiveQuests.Find(QuestID);
	const FQuestDefinitionRow* Row = FindQuestRow(QuestID);
	if (!State || !Row || State->bIsCompleted)
	{
		return;
	}

	State->CompletedObjectiveIDs.AddUnique(ObjectiveID);
	AdvanceStageIfReady(QuestID, Row, *State);
}

void UQuestManagerSubsystem::AdvanceStageIfReady(FName QuestID, const FQuestDefinitionRow* Row, FActiveQuestState& State)
{
	if (!Row->Stages.IsValidIndex(State.CurrentStageIndex))
	{
		return;
	}

	const FQuestStage& CurrentStage = Row->Stages[State.CurrentStageIndex];
	for (const FName& Required : CurrentStage.RequiredObjectiveIDs)
	{
		if (!State.CompletedObjectiveIDs.Contains(Required))
		{
			return; // still waiting on at least one objective in this stage
		}
	}

	State.CurrentStageIndex++;

	if (Row->Stages.IsValidIndex(State.CurrentStageIndex))
	{
		OnQuestStageAdvanced.Broadcast(QuestID, Row->Stages[State.CurrentStageIndex].StageID);
	}
	else
	{
		State.bIsCompleted = true;
		CompletedQuestIDs.Add(QuestID);
		OnQuestCompleted.Broadcast(QuestID);
	}
}

bool UQuestManagerSubsystem::IsQuestActive(FName QuestID) const
{
	const FActiveQuestState* State = ActiveQuests.Find(QuestID);
	return State && !State->bIsCompleted;
}

bool UQuestManagerSubsystem::IsQuestCompleted(FName QuestID) const
{
	return CompletedQuestIDs.Contains(QuestID);
}

FText UQuestManagerSubsystem::GetCurrentObjectiveText(FName QuestID) const
{
	const FActiveQuestState* State = ActiveQuests.Find(QuestID);
	const FQuestDefinitionRow* Row = FindQuestRow(QuestID);
	if (!State || !Row || !Row->Stages.IsValidIndex(State->CurrentStageIndex))
	{
		return FText::GetEmpty();
	}
	return Row->Stages[State->CurrentStageIndex].ObjectiveText;
}

void UQuestManagerSubsystem::RestoreQuestState(const TMap<FName, FActiveQuestState>& SavedState, const TArray<FName>& InCompletedQuestIDs)
{
	ActiveQuests = SavedState;
	CompletedQuestIDs.Reset();
	for (const FName& ID : InCompletedQuestIDs)
	{
		CompletedQuestIDs.Add(ID);
	}
}
