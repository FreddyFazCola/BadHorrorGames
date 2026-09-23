#include "SpellProjectileBase.h"
#include "SpellDefinition.h"
#include "Components/SphereComponent.h"
#include "GameFramework/ProjectileMovementComponent.h"
#include "NiagaraFunctionLibrary.h"
#include "Kismet/GameplayStatics.h"

ASpellProjectileBase::ASpellProjectileBase()
{
	PrimaryActorTick.bCanEverTick = false;

	CollisionComponent = CreateDefaultSubobject<USphereComponent>(TEXT("CollisionComponent"));
	CollisionComponent->InitSphereRadius(15.f);
	CollisionComponent->SetCollisionProfileName(TEXT("Projectile"));
	CollisionComponent->OnComponentHit.AddDynamic(this, &ASpellProjectileBase::OnProjectileHit);
	RootComponent = CollisionComponent;

	ProjectileMovement = CreateDefaultSubobject<UProjectileMovementComponent>(TEXT("ProjectileMovement"));
	ProjectileMovement->UpdatedComponent = CollisionComponent;
	ProjectileMovement->InitialSpeed = 2000.f;
	ProjectileMovement->MaxSpeed = 2000.f;
	ProjectileMovement->bRotationFollowsVelocity = true;
	ProjectileMovement->bShouldBounce = false;
	ProjectileMovement->ProjectileGravityScale = 0.f;

	SetReplicates(true);
}

void ASpellProjectileBase::BeginPlay()
{
	Super::BeginPlay();
	SetLifeSpan(LifeSpanSeconds);
}

void ASpellProjectileBase::InitializeFromSpell(USpellDefinition* InSpellDefinition)
{
	SourceSpell = InSpellDefinition;
}

void ASpellProjectileBase::OnProjectileHit(UPrimitiveComponent* HitComp, AActor* OtherActor, UPrimitiveComponent* OtherComp,
	FVector NormalImpulse, const FHitResult& Hit)
{
	if (!OtherActor || OtherActor == this || OtherActor == GetOwner())
	{
		return;
	}

	ApplyImpactDamage(OtherActor, Hit);

	if (SourceSpell && SourceSpell->CastEffect)
	{
		UNiagaraFunctionLibrary::SpawnSystemAtLocation(this, SourceSpell->CastEffect, Hit.Location, Hit.Normal.Rotation());
	}

	Destroy();
}

void ASpellProjectileBase::ApplyImpactDamage(AActor* OtherActor, const FHitResult& Hit)
{
	if (!SourceSpell || SourceSpell->DamageAmount <= 0.f)
	{
		return;
	}

	AController* InstigatorController = GetInstigatorController();
	UGameplayStatics::ApplyPointDamage(OtherActor, SourceSpell->DamageAmount, Hit.ImpactNormal, Hit,
		InstigatorController, this, nullptr);
}
