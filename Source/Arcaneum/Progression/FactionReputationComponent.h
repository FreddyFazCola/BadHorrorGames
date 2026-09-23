#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "FactionReputationComponent.generated.h"

/** The four Orders (house-equivalent) -- see Docs/WORLD_AND_FACTIONS.md. */
UENUM(BlueprintType)
enum class EArcaneumOrder : uint8
{
	Ember UMETA(DisplayName = "Order of Ember"),
	Deep UMETA(DisplayName = "Order of Deep"),
	Root UMETA(DisplayName = "Order of Root"),
	Gale UMETA(DisplayName = "Order of Gale")
};

DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FOnReputationChanged, EArcaneumOrder, Order, int32, NewValue);

/**
 * Tracks the player's standing with each of the four Orders. Nudged by dialogue
 * choices (see UDialogueComponent) and Order loyalty questline outcomes; read by the
 * multi-slide epilogue at the end of the main quest (Docs/QUEST_OUTLINE.md, mission 14).
 */
UCLASS(ClassGroup = (Arcaneum), meta = (BlueprintSpawnableComponent))
class ARCANEUM_API UFactionReputationComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UFactionReputationComponent();

	UPROPERTY(BlueprintAssignable, Category = "Faction")
	FOnReputationChanged OnReputationChanged;

	UFUNCTION(BlueprintCallable, Category = "Faction")
	void ChangeReputation(EArcaneumOrder Order, int32 Delta);

	UFUNCTION(BlueprintPure, Category = "Faction")
	int32 GetReputation(EArcaneumOrder Order) const;

	UFUNCTION(BlueprintPure, Category = "Faction")
	EArcaneumOrder GetHighestReputationOrder() const;

	UFUNCTION(BlueprintPure, Category = "Faction")
	const TMap<EArcaneumOrder, int32>& GetAllReputation() const { return Reputation; }

	/** Set once at Sorting (Docs/QUEST_OUTLINE.md mission 2, "The Trial of Four"); grants a standing head start. */
	UFUNCTION(BlueprintCallable, Category = "Faction")
	void SetHomeOrder(EArcaneumOrder Order);

	UFUNCTION(BlueprintPure, Category = "Faction")
	EArcaneumOrder GetHomeOrder() const { return HomeOrder; }

private:
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Faction")
	TMap<EArcaneumOrder, int32> Reputation;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Faction")
	EArcaneumOrder HomeOrder = EArcaneumOrder::Ember;

	bool bHomeOrderSet = false;
};
