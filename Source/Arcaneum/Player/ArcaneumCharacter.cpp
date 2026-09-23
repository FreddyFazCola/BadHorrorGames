#include "ArcaneumCharacter.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "GameFramework/SpringArmComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "EnhancedInputComponent.h"
#include "EnhancedInputSubsystems.h"
#include "InputActionValue.h"
#include "../Spells/SpellCastingComponent.h"
#include "../Spells/SpellDefinition.h"
#include "../Progression/FactionReputationComponent.h"

AArcaneumCharacter::AArcaneumCharacter()
{
	PrimaryActorTick.bCanEverTick = true;

	GetCapsuleComponent()->InitCapsuleSize(42.f, 96.f);

	bUseControllerRotationYaw = false;
	GetCharacterMovement()->bOrientRotationToMovement = true;
	GetCharacterMovement()->RotationRate = FRotator(0.f, 500.f, 0.f);

	CameraBoom = CreateDefaultSubobject<USpringArmComponent>(TEXT("CameraBoom"));
	CameraBoom->SetupAttachment(RootComponent);
	CameraBoom->TargetArmLength = 400.f;
	CameraBoom->bUsePawnControlRotation = true;

	FollowCamera = CreateDefaultSubobject<UCameraComponent>(TEXT("FollowCamera"));
	FollowCamera->SetupAttachment(CameraBoom, USpringArmComponent::SocketName);
	FollowCamera->bUsePawnControlRotation = false;

	SpellCasting = CreateDefaultSubobject<USpellCastingComponent>(TEXT("SpellCasting"));
	FactionReputation = CreateDefaultSubobject<UFactionReputationComponent>(TEXT("FactionReputation"));
}

void AArcaneumCharacter::BeginPlay()
{
	Super::BeginPlay();

	if (APlayerController* PC = Cast<APlayerController>(Controller))
	{
		if (UEnhancedInputLocalPlayerSubsystem* Subsystem = ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(PC->GetLocalPlayer()))
		{
			if (DefaultMappingContext)
			{
				Subsystem->AddMappingContext(DefaultMappingContext, 0);
			}
		}
	}
}

void AArcaneumCharacter::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	Super::SetupPlayerInputComponent(PlayerInputComponent);

	UEnhancedInputComponent* EnhancedInput = Cast<UEnhancedInputComponent>(PlayerInputComponent);
	if (!EnhancedInput)
	{
		return;
	}

	if (MoveAction)
	{
		EnhancedInput->BindAction(MoveAction, ETriggerEvent::Triggered, this, &AArcaneumCharacter::Move);
	}
	if (LookAction)
	{
		EnhancedInput->BindAction(LookAction, ETriggerEvent::Triggered, this, &AArcaneumCharacter::Look);
	}
	if (JumpAction)
	{
		EnhancedInput->BindAction(JumpAction, ETriggerEvent::Started, this, &ACharacter::Jump);
		EnhancedInput->BindAction(JumpAction, ETriggerEvent::Completed, this, &ACharacter::StopJumping);
	}
	if (CastPrimarySpellAction)
	{
		EnhancedInput->BindAction(CastPrimarySpellAction, ETriggerEvent::Started, this, &AArcaneumCharacter::CastPrimarySpell);
	}
	if (CastSecondarySpellAction)
	{
		EnhancedInput->BindAction(CastSecondarySpellAction, ETriggerEvent::Started, this, &AArcaneumCharacter::CastSecondarySpell);
	}
	if (CycleSpellAction)
	{
		EnhancedInput->BindAction(CycleSpellAction, ETriggerEvent::Started, this, &AArcaneumCharacter::CycleEquippedSpell);
	}
}

void AArcaneumCharacter::Move(const FInputActionValue& Value)
{
	if (!Controller)
	{
		return;
	}

	const FVector2D MovementVector = Value.Get<FVector2D>();
	const FRotator YawRotation(0.f, Controller->GetControlRotation().Yaw, 0.f);
	const FVector ForwardDirection = FRotationMatrix(YawRotation).GetUnitAxis(EAxis::X);
	const FVector RightDirection = FRotationMatrix(YawRotation).GetUnitAxis(EAxis::Y);

	AddMovementInput(ForwardDirection, MovementVector.Y);
	AddMovementInput(RightDirection, MovementVector.X);
}

void AArcaneumCharacter::Look(const FInputActionValue& Value)
{
	if (!Controller)
	{
		return;
	}

	const FVector2D LookAxisVector = Value.Get<FVector2D>();
	AddControllerYawInput(LookAxisVector.X);
	AddControllerPitchInput(LookAxisVector.Y);
}

void AArcaneumCharacter::CastPrimarySpell()
{
	if (SpellCasting && EquippedSpells.IsValidIndex(0))
	{
		SpellCasting->TryCastSpell(EquippedSpells[0]);
	}
}

void AArcaneumCharacter::CastSecondarySpell()
{
	if (SpellCasting && EquippedSpells.IsValidIndex(1))
	{
		SpellCasting->TryCastSpell(EquippedSpells[1]);
	}
}

void AArcaneumCharacter::CycleEquippedSpell()
{
	if (!SpellCasting || SpellCasting->GetKnownSpells().Num() == 0)
	{
		return;
	}

	CycleIndex = (CycleIndex + 1) % SpellCasting->GetKnownSpells().Num();
	EquippedSpells.SetNum(FMath::Max(EquippedSpells.Num(), 1));
	EquippedSpells[0] = SpellCasting->GetKnownSpells()[CycleIndex];
}
