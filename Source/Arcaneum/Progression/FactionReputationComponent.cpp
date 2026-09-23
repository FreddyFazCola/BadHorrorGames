#include "FactionReputationComponent.h"

UFactionReputationComponent::UFactionReputationComponent()
{
	PrimaryComponentTick.bCanEverTick = false;

	Reputation.Add(EArcaneumOrder::Ember, 0);
	Reputation.Add(EArcaneumOrder::Deep, 0);
	Reputation.Add(EArcaneumOrder::Root, 0);
	Reputation.Add(EArcaneumOrder::Gale, 0);
}

void UFactionReputationComponent::ChangeReputation(EArcaneumOrder Order, int32 Delta)
{
	int32& Value = Reputation.FindOrAdd(Order);
	Value += Delta;
	OnReputationChanged.Broadcast(Order, Value);
}

int32 UFactionReputationComponent::GetReputation(EArcaneumOrder Order) const
{
	const int32* Value = Reputation.Find(Order);
	return Value ? *Value : 0;
}

EArcaneumOrder UFactionReputationComponent::GetHighestReputationOrder() const
{
	EArcaneumOrder Best = EArcaneumOrder::Ember;
	int32 BestValue = TNumericLimits<int32>::Min();

	for (const TPair<EArcaneumOrder, int32>& Pair : Reputation)
	{
		if (Pair.Value > BestValue)
		{
			BestValue = Pair.Value;
			Best = Pair.Key;
		}
	}
	return Best;
}

void UFactionReputationComponent::SetHomeOrder(EArcaneumOrder Order)
{
	if (bHomeOrderSet)
	{
		return;
	}
	HomeOrder = Order;
	bHomeOrderSet = true;
	ChangeReputation(Order, 10);
}
