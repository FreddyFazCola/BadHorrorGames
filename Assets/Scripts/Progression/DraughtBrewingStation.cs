using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Events;

namespace Arcaneum
{
    [System.Serializable] public class DraughtEvent : UnityEvent<DraughtRecipe> { }

    /// <summary>
    /// Attach to a greenhouse/brewing-table prop (see Docs/QUEST_OUTLINE.md's Root loyalty
    /// quest, "Roots That Hold"). Tracks a simple ingredient inventory and brews a recipe
    /// over brewSeconds, then applies its effect to whichever PlayerHealth/SpellCasting is
    /// passed to Brew. Ingredient sourcing (where the inventory counts come from) is left to
    /// whatever pickup/shop system is built later -- call AddIngredient from that.
    /// </summary>
    public class DraughtBrewingStation : MonoBehaviour
    {
        public DraughtEvent onBrewStarted;
        public DraughtEvent onBrewCompleted;

        private readonly Dictionary<string, int> ingredientCounts = new Dictionary<string, int>();
        private bool isBrewing;

        public void AddIngredient(string ingredientId, int amount = 1)
        {
            ingredientCounts[ingredientId] = ingredientCounts.TryGetValue(ingredientId, out var c) ? c + amount : amount;
        }

        public bool HasIngredients(DraughtRecipe recipe)
        {
            foreach (var ingredient in recipe.ingredients)
            {
                if (!ingredientCounts.TryGetValue(ingredient.ingredientId, out var have) || have < ingredient.quantity)
                    return false;
            }
            return true;
        }

        public bool TryBrew(DraughtRecipe recipe, PlayerHealth health, SpellCasting casting)
        {
            if (isBrewing || recipe == null || !HasIngredients(recipe)) return false;

            foreach (var ingredient in recipe.ingredients)
                ingredientCounts[ingredient.ingredientId] -= ingredient.quantity;

            isBrewing = true;
            onBrewStarted?.Invoke(recipe);
            StartCoroutine(BrewRoutine(recipe, health, casting));
            return true;
        }

        private System.Collections.IEnumerator BrewRoutine(DraughtRecipe recipe, PlayerHealth health, SpellCasting casting)
        {
            yield return new WaitForSeconds(recipe.brewSeconds);

            if (health != null && recipe.healAmount > 0f) health.Heal(recipe.healAmount);
            if (casting != null && recipe.manaRestoreAmount > 0f) casting.RestoreMana(recipe.manaRestoreAmount);
            isBrewing = false;
            onBrewCompleted?.Invoke(recipe);
        }
    }
}
