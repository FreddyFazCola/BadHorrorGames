#pragma once

#include "CoreMinimal.h"
#include "SpellTypes.generated.h"

/**
 * The four schools of Sigilcraft (see Docs/STORY_BIBLE.md).
 * Cantrip = utility/exploration, Binding = offense/debuff,
 * Warding = defense/control, Conjury = summon/ultimate.
 */
UENUM(BlueprintType)
enum class ESpellCategory : uint8
{
	Cantrip UMETA(DisplayName = "Cantrip"),
	Binding UMETA(DisplayName = "Binding"),
	Warding UMETA(DisplayName = "Warding"),
	Conjury UMETA(DisplayName = "Conjury")
};

UENUM(BlueprintType)
enum class ESpellCastResult : uint8
{
	Success,
	NotLearned,
	InsufficientMana,
	OnCooldown
};
