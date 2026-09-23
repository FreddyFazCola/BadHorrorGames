#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "SpellTypes.h"
#include "SpellDefinition.generated.h"

class ASpellProjectileBase;
class UAnimMontage;
class USoundBase;
class UNiagaraSystem;

/**
 * Data-driven definition of a single spell (see Docs/SPELL_LIST.md for the full roster).
 * Designers add new spells by creating data asset instances of this class in the Unreal
 * Editor (or a Blueprint subclass to assign asset references) -- no C++ changes required.
 */
UCLASS(BlueprintType)
class ARCANEUM_API USpellDefinition : public UPrimaryDataAsset
{
	GENERATED_BODY()

public:
	/** Unique identifier used by save games, quest unlock hooks, and UI lookups. */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Spell")
	FName SpellID;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Spell")
	FText DisplayName;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Spell", meta = (MultiLine = "true"))
	FText Description;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Spell")
	ESpellCategory Category = ESpellCategory::Cantrip;

	/** Story-progression tier required before this spell can be learned (1-5, see Docs/SPELL_LIST.md). */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Spell", meta = (ClampMin = "1", ClampMax = "5"))
	int32 RequiredTier = 1;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Spell|Cost")
	float ManaCost = 10.f;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Spell|Cost")
	float CooldownSeconds = 5.f;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Spell|Effect")
	float DamageAmount = 0.f;

	/**
	 * If set, casting spawns this projectile actor. If null, the spell resolves as an
	 * instant/self effect (e.g. a buff Warding like Stonehide) applied directly by
	 * USpellCastingComponent instead.
	 */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Spell|Effect")
	TSubclassOf<ASpellProjectileBase> ProjectileClass;

	/** Assigned on a Blueprint child of this data asset once the animation pack is imported. */
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Spell|Presentation")
	TObjectPtr<UAnimMontage> CastMontage;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Spell|Presentation")
	TObjectPtr<UNiagaraSystem> CastEffect;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Spell|Presentation")
	TObjectPtr<USoundBase> CastSound;

	//~ Begin UPrimaryDataAsset Interface
	virtual FPrimaryAssetId GetPrimaryAssetId() const override
	{
		return FPrimaryAssetId(TEXT("Spell"), SpellID);
	}
	//~ End UPrimaryDataAsset Interface
};
