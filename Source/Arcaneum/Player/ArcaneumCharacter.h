#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "ArcaneumCharacter.generated.h"

class USpringArmComponent;
class UCameraComponent;
class USpellCastingComponent;
class UFactionReputationComponent;
class UInputMappingContext;
class UInputAction;
class USpellDefinition;
struct FInputActionValue;

/**
 * Base player character. Movement/camera/input plumbing lives here in C++;
 * mesh, animation blueprint, and Input Action/Mapping Context assets are
 * assigned on a Blueprint child (Content/Blueprints/BP_ArcaneumCharacter)
 * once licensed art/animation packs are imported -- see root README.md.
 */
UCLASS()
class ARCANEUM_API AArcaneumCharacter : public ACharacter
{
	GENERATED_BODY()

public:
	AArcaneumCharacter();

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Camera")
	TObjectPtr<USpringArmComponent> CameraBoom;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Camera")
	TObjectPtr<UCameraComponent> FollowCamera;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Spells")
	TObjectPtr<USpellCastingComponent> SpellCasting;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Progression")
	TObjectPtr<UFactionReputationComponent> FactionReputation;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Input")
	TObjectPtr<UInputMappingContext> DefaultMappingContext;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Input")
	TObjectPtr<UInputAction> MoveAction;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Input")
	TObjectPtr<UInputAction> LookAction;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Input")
	TObjectPtr<UInputAction> JumpAction;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Input")
	TObjectPtr<UInputAction> CastPrimarySpellAction;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Input")
	TObjectPtr<UInputAction> CastSecondarySpellAction;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Input")
	TObjectPtr<UInputAction> CycleSpellAction;

	/** Quick-cast slots; index 0 = primary, 1 = secondary. Populated via UI/quest hooks. */
	UPROPERTY(BlueprintReadWrite, Category = "Spells")
	TArray<TObjectPtr<USpellDefinition>> EquippedSpells;

protected:
	virtual void BeginPlay() override;
	virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;

	void Move(const FInputActionValue& Value);
	void Look(const FInputActionValue& Value);
	void CastPrimarySpell();
	void CastSecondarySpell();
	void CycleEquippedSpell();

private:
	int32 CycleIndex = 0;
};
