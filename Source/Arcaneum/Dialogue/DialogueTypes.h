#pragma once

#include "CoreMinimal.h"
#include "Engine/DataTable.h"
#include "DialogueTypes.generated.h"

USTRUCT(BlueprintType)
struct FDialogueChoice
{
	GENERATED_BODY()

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Dialogue")
	FText ChoiceText;

	/** RowName of the next FDialogueLine to jump to; None ends the conversation. */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Dialogue")
	FName NextLineID;

	/** Optional: completes this objective on the given quest when picked (UQuestManagerSubsystem::CompleteObjective). */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Dialogue")
	FName QuestIDToUpdate;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Dialogue")
	FName ObjectiveIDToComplete;

	/** Optional: nudges the player's Order standing (EArcaneumOrder in FactionReputationComponent.h). */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Dialogue")
	bool bAffectsFactionReputation = false;

	/** Matches EArcaneumOrder's enum value; kept as uint8 here so this header doesn't need Progression/ as a dependency. */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Dialogue", meta = (EditCondition = "bAffectsFactionReputation"))
	uint8 FactionOrderIndex = 0;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Dialogue", meta = (EditCondition = "bAffectsFactionReputation"))
	int32 ReputationDelta = 0;
};

/** One row of a dialogue DataTable; RowName is the line ID. */
USTRUCT(BlueprintType)
struct FDialogueLine : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Dialogue")
	FText SpeakerName;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Dialogue", meta = (MultiLine = "true"))
	FText LineText;

	/** Empty = a single "Continue" advances via NextLineIDIfNoChoices; non-empty = branching choices shown instead. */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Dialogue")
	TArray<FDialogueChoice> Choices;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Dialogue")
	FName NextLineIDIfNoChoices;
};
