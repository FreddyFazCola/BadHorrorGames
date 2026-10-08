using System.Collections.Generic;
using UnityEngine;

namespace Arcaneum
{
    [System.Serializable]
    public class DraughtIngredient
    {
        public string ingredientId;
        public int quantity = 1;
    }

    /// <summary>
    /// A brewable Draught (the Order of Root's potion-equivalent crafting system, see
    /// Docs/STORY_BIBLE.md). Create one asset per recipe via Assets > Create > Arcaneum >
    /// Draught Recipe.
    /// </summary>
    [CreateAssetMenu(fileName = "Draught_", menuName = "Arcaneum/Draught Recipe")]
    public class DraughtRecipe : ScriptableObject
    {
        public string draughtId;
        public string displayName;
        [TextArea] public string description;
        public List<DraughtIngredient> ingredients = new List<DraughtIngredient>();
        public float brewSeconds = 3f;

        [Header("Effect on brew complete")]
        public float healAmount = 0f;
        public float manaRestoreAmount = 0f;
    }
}
