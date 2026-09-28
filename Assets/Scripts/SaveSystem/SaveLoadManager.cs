using System.IO;
using UnityEngine;

namespace Arcaneum
{
    /// <summary>
    /// Working save/load via JsonUtility + Application.persistentDataPath. This part is fully
    /// functional as written (no engine-editor step required) -- what's still missing is the
    /// menu/UI code that builds a SaveData from the live game state and calls Save(), and that
    /// applies a loaded SaveData back onto QuestManager/SpellCasting/FactionReputation.
    /// </summary>
    public static class SaveLoadManager
    {
        private static string SavePath(string slot) =>
            Path.Combine(Application.persistentDataPath, $"arcaneum_save_{slot}.json");

        public static void Save(SaveData data, string slot = "1")
        {
            string json = JsonUtility.ToJson(data, true);
            File.WriteAllText(SavePath(slot), json);
        }

        public static SaveData Load(string slot = "1")
        {
            string path = SavePath(slot);
            if (!File.Exists(path)) return null;
            string json = File.ReadAllText(path);
            return JsonUtility.FromJson<SaveData>(json);
        }

        public static bool SaveExists(string slot = "1") => File.Exists(SavePath(slot));
    }
}
