#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "ArcaneumGameMode.generated.h"

UCLASS()
class ARCANEUM_API AArcaneumGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	AArcaneumGameMode();

protected:
	virtual void BeginPlay() override;
};
