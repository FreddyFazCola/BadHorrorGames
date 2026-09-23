#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "DialogueTypes.h"
#include "DialogueComponent.generated.h"

class UDataTable;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnDialogueLineChanged, FDialogueLine, NewLine);
DECLARE_DYNAMIC_MULTICAST_DELEGATE(FOnDialogueEnded);

/**
 * Attach to an NPC actor to give it a branching conversation authored as rows in
 * DialogueTable. A UMG dialogue widget binds to OnDialogueLineChanged/OnDialogueEnded
 * and calls SelectChoice/AdvanceWithNoChoice in response to player input.
 */
UCLASS(ClassGroup = (Arcaneum), meta = (BlueprintSpawnableComponent))
class ARCANEUM_API UDialogueComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Dialogue")
	TObjectPtr<UDataTable> DialogueTable;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Dialogue")
	FName StartLineID;

	UPROPERTY(BlueprintAssignable, Category = "Dialogue")
	FOnDialogueLineChanged OnDialogueLineChanged;

	UPROPERTY(BlueprintAssignable, Category = "Dialogue")
	FOnDialogueEnded OnDialogueEnded;

	UFUNCTION(BlueprintCallable, Category = "Dialogue")
	void StartDialogue();

	UFUNCTION(BlueprintCallable, Category = "Dialogue")
	void SelectChoice(int32 ChoiceIndex);

	UFUNCTION(BlueprintCallable, Category = "Dialogue")
	void AdvanceWithNoChoice();

	UFUNCTION(BlueprintPure, Category = "Dialogue")
	bool IsInConversation() const { return !CurrentLineID.IsNone(); }

private:
	FName CurrentLineID;

	void GoToLine(FName LineID);
	const FDialogueLine* FindLine(FName LineID) const;
};
