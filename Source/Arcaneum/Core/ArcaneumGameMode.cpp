#include "ArcaneumGameMode.h"
#include "../Player/ArcaneumCharacter.h"
#include "../Quests/QuestManagerSubsystem.h"
#include "Kismet/GameplayStatics.h"

AArcaneumGameMode::AArcaneumGameMode()
{
	DefaultPawnClass = AArcaneumCharacter::StaticClass();
}

void AArcaneumGameMode::BeginPlay()
{
	Super::BeginPlay();

	// Auto-starts the prologue mission on a fresh game (see Docs/QUEST_OUTLINE.md, "Late
	// Admission"). Loading an existing save should restore quest state from
	// UArcaneumSaveGame instead of calling this -- wire that up in a save/load manager
	// once the main menu flow exists.
	if (UGameInstance* GameInstance = GetGameInstance())
	{
		if (UQuestManagerSubsystem* QuestManager = GameInstance->GetSubsystem<UQuestManagerSubsystem>())
		{
			QuestManager->StartQuest(FName(TEXT("Q01_LateAdmission")));
		}
	}
}
