#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "SpellTypes.h"
#include "SpellCastingComponent.generated.h"

class USpellDefinition;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnSpellCast, USpellDefinition*, CastSpell);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnManaChanged, float, NewManaFraction);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnSpellLearned, USpellDefinition*, LearnedSpell);

/**
 * Owns mana, cooldowns, known spells, and cast resolution for whatever actor it's
 * attached to (the player character, and potentially spellcasting NPC enemies).
 * Attach a UAnimMontage-driven cast animation by binding to OnSpellCast in a
 * Blueprint child of ArcaneumCharacter (see Source/Arcaneum/Player).
 */
UCLASS(ClassGroup = (Arcaneum), meta = (BlueprintSpawnableComponent))
class ARCANEUM_API USpellCastingComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	USpellCastingComponent();

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Mana")
	float MaxMana = 100.f;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Mana")
	float ManaRegenPerSecond = 5.f;

	UPROPERTY(BlueprintReadOnly, Category = "Mana")
	float CurrentMana = 100.f;

	/** Highest story-progression tier unlocked so far; gates LearnSpell (see Docs/SPELL_LIST.md). */
	UPROPERTY(BlueprintReadOnly, Category = "Progression")
	int32 CurrentTier = 1;

	UPROPERTY(BlueprintAssignable, Category = "Spells")
	FOnSpellCast OnSpellCast;

	UPROPERTY(BlueprintAssignable, Category = "Spells")
	FOnManaChanged OnManaChanged;

	UPROPERTY(BlueprintAssignable, Category = "Spells")
	FOnSpellLearned OnSpellLearned;

	/** Attempts to cast; returns why it failed if it did, so UI can show the right feedback. */
	UFUNCTION(BlueprintCallable, Category = "Spells")
	ESpellCastResult TryCastSpell(USpellDefinition* Spell);

	/** Called by UQuestManagerSubsystem when a mission teaches a new spell. */
	UFUNCTION(BlueprintCallable, Category = "Spells")
	bool LearnSpell(USpellDefinition* Spell);

	UFUNCTION(BlueprintCallable, Category = "Spells")
	void SetCurrentTier(int32 NewTier);

	UFUNCTION(BlueprintPure, Category = "Spells")
	bool IsSpellKnown(USpellDefinition* Spell) const;

	UFUNCTION(BlueprintPure, Category = "Spells")
	bool IsSpellOnCooldown(USpellDefinition* Spell) const;

	UFUNCTION(BlueprintPure, Category = "Spells")
	const TArray<TObjectPtr<USpellDefinition>>& GetKnownSpells() const { return KnownSpells; }

protected:
	virtual void BeginPlay() override;
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

private:
	UPROPERTY()
	TArray<TObjectPtr<USpellDefinition>> KnownSpells;

	UPROPERTY()
	TMap<TObjectPtr<USpellDefinition>, float> CooldownRemaining;

	void ApplySpellEffect(USpellDefinition* Spell);
};
