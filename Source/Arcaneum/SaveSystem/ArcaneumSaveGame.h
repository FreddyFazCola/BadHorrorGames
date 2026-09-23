#pragma once

#include "CoreMinimal.h"
#include "GameFramework/SaveGame.h"
#include "../Quests/QuestTypes.h"
#include "../Progression/FactionReputationComponent.h"
#include "ArcaneumSaveGame.generated.h"

USTRUCT(BlueprintType)
struct FArcaneumSavedReputation
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadWrite, Category = "Save")
	EArcaneumOrder Order = EArcaneumOrder::Ember;

	UPROPERTY(BlueprintReadWrite, Category = "Save")
	int32 Value = 0;
};

/**
 * Full save-file payload. A save/load manager (not yet implemented -- see root README's
 * roadmap) is responsible for populating this from UQuestManagerSubsystem/
 * USpellCastingComponent/UFactionReputationComponent on save, and restoring them
 * (via RestoreQuestState, LearnSpell per UnlockedSpellIDs, ChangeReputation per entry)
 * on load.
 */
UCLASS()
class ARCANEUM_API UArcaneumSaveGame : public USaveGame
{
	GENERATED_BODY()

public:
	UPROPERTY(BlueprintReadWrite, Category = "Save")
	FString SlotDisplayName;

	UPROPERTY(BlueprintReadWrite, Category = "Save")
	FDateTime SaveTimestamp;

	UPROPERTY(BlueprintReadWrite, Category = "Save")
	FName CurrentLevelName;

	UPROPERTY(BlueprintReadWrite, Category = "Save")
	FVector PlayerLocation = FVector::ZeroVector;

	UPROPERTY(BlueprintReadWrite, Category = "Save")
	FRotator PlayerRotation = FRotator::ZeroRotator;

	UPROPERTY(BlueprintReadWrite, Category = "Save")
	TArray<FName> UnlockedSpellIDs;

	UPROPERTY(BlueprintReadWrite, Category = "Save")
	int32 CurrentSpellTier = 1;

	UPROPERTY(BlueprintReadWrite, Category = "Save")
	TMap<FName, FActiveQuestState> ActiveQuestStates;

	UPROPERTY(BlueprintReadWrite, Category = "Save")
	TArray<FName> CompletedQuestIDs;

	UPROPERTY(BlueprintReadWrite, Category = "Save")
	TArray<FArcaneumSavedReputation> FactionReputation;

	UPROPERTY(BlueprintReadWrite, Category = "Save")
	EArcaneumOrder HomeOrder = EArcaneumOrder::Ember;
};
