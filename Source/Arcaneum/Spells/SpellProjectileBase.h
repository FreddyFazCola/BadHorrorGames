#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "SpellProjectileBase.generated.h"

class USpellDefinition;
class UProjectileMovementComponent;
class USphereComponent;

/**
 * Base class for spawned spell projectiles (Emberburst, Tempest Lance, etc).
 * Visuals (mesh/Niagara trail) are assigned on a Blueprint child in-editor;
 * this class only owns collision, movement, and damage-on-hit logic.
 */
UCLASS(Abstract)
class ARCANEUM_API ASpellProjectileBase : public AActor
{
	GENERATED_BODY()

public:
	ASpellProjectileBase();

	/** Called by USpellCastingComponent immediately after spawning. */
	void InitializeFromSpell(USpellDefinition* InSpellDefinition);

protected:
	virtual void BeginPlay() override;

	UFUNCTION()
	void OnProjectileHit(UPrimitiveComponent* HitComp, AActor* OtherActor, UPrimitiveComponent* OtherComp,
		FVector NormalImpulse, const FHitResult& Hit);

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Components")
	TObjectPtr<USphereComponent> CollisionComponent;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Components")
	TObjectPtr<UProjectileMovementComponent> ProjectileMovement;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Spell")
	float LifeSpanSeconds = 5.f;

	UPROPERTY(BlueprintReadOnly, Category = "Spell")
	TObjectPtr<USpellDefinition> SourceSpell;

private:
	void ApplyImpactDamage(AActor* OtherActor, const FHitResult& Hit);
};
