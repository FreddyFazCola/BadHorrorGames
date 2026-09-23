#pragma once

#include "CoreMinimal.h"
#include "Engine/DataTable.h"
#include "QuestTypes.generated.h"

/** One step within a quest. See Docs/QUEST_OUTLINE.md for the authored 14-mission main quest. */
USTRUCT(BlueprintType)
struct FQuestStage
{
	GENERATED_BODY()

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Quest")
	FName StageID;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Quest", meta = (MultiLine = "true"))
	FText ObjectiveText;

	/** All of these objective IDs must be completed (via CompleteObjective) before the stage advances. */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Quest")
	TArray<FName> RequiredObjectiveIDs;

	/** FName matching a USpellDefinition::SpellID to grant on reaching this stage; None = no spell granted. */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Quest")
	FName GrantsSpellID;
};

/** One row of the quest DataTable; RowName is the QuestID (e.g. "Q01_LateAdmission"). */
USTRUCT(BlueprintType)
struct FQuestDefinitionRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Quest")
	FText DisplayName;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Quest")
	int32 ActNumber = 1;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Quest")
	int32 MissionNumber = 1;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Quest")
	bool bIsMainQuest = true;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Quest")
	TArray<FQuestStage> Stages;

	/** RowName of a quest that must be completed before this one can be started; None = unrestricted. */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Quest")
	FName PrerequisiteQuestID;
};

/** Runtime progress for one in-progress or completed quest; this is what gets serialized into the save game. */
USTRUCT(BlueprintType)
struct FActiveQuestState
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Quest")
	FName QuestID;

	UPROPERTY(BlueprintReadOnly, Category = "Quest")
	int32 CurrentStageIndex = 0;

	UPROPERTY(BlueprintReadOnly, Category = "Quest")
	TArray<FName> CompletedObjectiveIDs;

	UPROPERTY(BlueprintReadOnly, Category = "Quest")
	bool bIsCompleted = false;
};
