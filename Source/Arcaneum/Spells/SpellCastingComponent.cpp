#include "SpellCastingComponent.h"
#include "SpellDefinition.h"
#include "SpellProjectileBase.h"
#include "NiagaraFunctionLibrary.h"
#include "Kismet/GameplayStatics.h"

USpellCastingComponent::USpellCastingComponent()
{
	PrimaryComponentTick.bCanEverTick = true;
}

void USpellCastingComponent::BeginPlay()
{
	Super::BeginPlay();
	CurrentMana = MaxMana;
}

void USpellCastingComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);

	if (CurrentMana < MaxMana)
	{
		CurrentMana = FMath::Min(MaxMana, CurrentMana + ManaRegenPerSecond * DeltaTime);
		OnManaChanged.Broadcast(MaxMana > 0.f ? CurrentMana / MaxMana : 0.f);
	}

	for (auto& Pair : CooldownRemaining)
	{
		if (Pair.Value > 0.f)
		{
			Pair.Value = FMath::Max(0.f, Pair.Value - DeltaTime);
		}
	}
}

bool USpellCastingComponent::IsSpellKnown(USpellDefinition* Spell) const
{
	return Spell && KnownSpells.Contains(Spell);
}

bool USpellCastingComponent::IsSpellOnCooldown(USpellDefinition* Spell) const
{
	const float* Remaining = CooldownRemaining.Find(Spell);
	return Remaining && *Remaining > 0.f;
}

bool USpellCastingComponent::LearnSpell(USpellDefinition* Spell)
{
	if (!Spell || Spell->RequiredTier > CurrentTier || IsSpellKnown(Spell))
	{
		return false;
	}

	KnownSpells.Add(Spell);
	CooldownRemaining.Add(Spell, 0.f);
	OnSpellLearned.Broadcast(Spell);
	return true;
}

void USpellCastingComponent::SetCurrentTier(int32 NewTier)
{
	CurrentTier = FMath::Max(CurrentTier, NewTier);
}

ESpellCastResult USpellCastingComponent::TryCastSpell(USpellDefinition* Spell)
{
	if (!IsSpellKnown(Spell))
	{
		return ESpellCastResult::NotLearned;
	}

	if (IsSpellOnCooldown(Spell))
	{
		return ESpellCastResult::OnCooldown;
	}

	if (CurrentMana < Spell->ManaCost)
	{
		return ESpellCastResult::InsufficientMana;
	}

	CurrentMana -= Spell->ManaCost;
	CooldownRemaining.Add(Spell, Spell->CooldownSeconds);
	OnManaChanged.Broadcast(MaxMana > 0.f ? CurrentMana / MaxMana : 0.f);

	ApplySpellEffect(Spell);
	OnSpellCast.Broadcast(Spell);

	return ESpellCastResult::Success;
}

void USpellCastingComponent::ApplySpellEffect(USpellDefinition* Spell)
{
	AActor* Owner = GetOwner();
	if (!Owner)
	{
		return;
	}

	if (Spell->CastEffect)
	{
		UNiagaraFunctionLibrary::SpawnSystemAttached(Spell->CastEffect, Owner->GetRootComponent(), NAME_None,
			FVector::ZeroVector, FRotator::ZeroRotator, EAttachLocation::SnapToTarget, true);
	}

	if (Spell->CastSound)
	{
		UGameplayStatics::PlaySoundAtLocation(Owner, Spell->CastSound, Owner->GetActorLocation());
	}

	if (Spell->ProjectileClass)
	{
		UWorld* World = Owner->GetWorld();
		if (!World)
		{
			return;
		}

		const FVector SpawnLocation = Owner->GetActorLocation() + Owner->GetActorForwardVector() * 100.f;
		const FRotator SpawnRotation = Owner->GetActorRotation();

		FActorSpawnParameters SpawnParams;
		SpawnParams.Owner = Owner;
		SpawnParams.Instigator = Owner->GetInstigator();
		SpawnParams.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

		if (ASpellProjectileBase* Projectile = World->SpawnActor<ASpellProjectileBase>(Spell->ProjectileClass, SpawnLocation, SpawnRotation, SpawnParams))
		{
			Projectile->InitializeFromSpell(Spell);
		}
	}
	// Spells without a ProjectileClass (self/instant effects like Aegis Ward, Stonehide)
	// are expected to be handled by dedicated buff logic as those systems are built out;
	// this is the single point to extend when that lands.
}
