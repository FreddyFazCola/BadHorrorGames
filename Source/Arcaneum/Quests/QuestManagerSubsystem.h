#pragma once

#include "CoreMinimal.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "QuestTypes.h"
#include "QuestManagerSubsystem.generated.h"

class UDataTable;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnQuestStarted, FName, QuestID);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FOnQuestStageAdvanced, FName, QuestID, FName, NewStageID);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnQuestCompleted, FName, QuestID);

/**
 * Data-driven quest state machine, one instance per GameInstance. Missions are authored
 * as rows of QuestDataTable (RowName = QuestID) instead of hardcoded in C++ -- see
 * Docs/QUEST_OUTLINE.md for the 14-mission main quest this is designed to drive.
 * Assign QuestDataTable on a Blueprint child or via project defaults once the data
 * table asset is created in-editor.
 */
UCLASS()
class ARCANEUM_API UQuestManagerSubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Quest")
	TObjectPtr<UDataTable> QuestDataTable;

	UPROPERTY(BlueprintAssignable, Category = "Quest")
	FOnQuestStarted OnQuestStarted;

	UPROPERTY(BlueprintAssignable, Category = "Quest")
	FOnQuestStageAdvanced OnQuestStageAdvanced;

	UPROPERTY(BlueprintAssignable, Category = "Quest")
	FOnQuestCompleted OnQuestCompleted;

	UFUNCTION(BlueprintCallable, Category = "Quest")
	bool StartQuest(FName QuestID);

	/** Call when a trigger/dialogue choice/kill-count/etc satisfies one objective of the quest's current stage. */
	UFUNCTION(BlueprintCallable, Category = "Quest")
	void CompleteObjective(FName QuestID, FName ObjectiveID);

	UFUNCTION(BlueprintPure, Category = "Quest")
	bool IsQuestActive(FName QuestID) const;

	UFUNCTION(BlueprintPure, Category = "Quest")
	bool IsQuestCompleted(FName QuestID) const;

	UFUNCTION(BlueprintPure, Category = "Quest")
	FText GetCurrentObjectiveText(FName QuestID) const;

	UFUNCTION(BlueprintPure, Category = "Quest")
	const TMap<FName, FActiveQuestState>& GetActiveQuests() const { return ActiveQuests; }

	/** Restores progress from a loaded UArcaneumSaveGame. */
	UFUNCTION(BlueprintCallable, Category = "Quest")
	void RestoreQuestState(const TMap<FName, FActiveQuestState>& SavedState, const TArray<FName>& InCompletedQuestIDs);

private:
	UPROPERTY()
	TMap<FName, FActiveQuestState> ActiveQuests;

	UPROPERTY()
	TSet<FName> CompletedQuestIDs;

	const FQuestDefinitionRow* FindQuestRow(FName QuestID) const;
	void AdvanceStageIfReady(FName QuestID, const FQuestDefinitionRow* Row, FActiveQuestState& State);
};
