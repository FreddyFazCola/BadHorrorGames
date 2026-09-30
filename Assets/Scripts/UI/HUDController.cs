using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace Arcaneum
{
    /// <summary>
    /// Builds a functional HUD entirely from code at runtime -- no Canvas prefab, no
    /// TextMeshPro dependency (uses the legacy UnityEngine.UI.Text/Image so this has zero
    /// package-import risk). This exists so the events SpellCasting/QuestManager/
    /// DialogueRunner already broadcast are actually visible in-game before a real,
    /// artist-built UI exists. Replace this with a proper Canvas/UI Toolkit design once
    /// there's art direction for it -- this is deliberately plain, not final.
    ///
    /// Usage: put this on any GameObject in your scene (an empty "HUD" object is fine) and
    /// assign playerSpellCasting / playerHealth in the Inspector. Call ShowDialogue(runner)
    /// from whatever triggers a conversation (e.g. an interaction script on the NPC).
    /// </summary>
    public class HUDController : MonoBehaviour
    {
        [Header("Bind these to the player")]
        public SpellCasting playerSpellCasting;
        public PlayerHealth playerHealth;
        public string trackedMainQuestId = "Q01_LateAdmission";

        private Image manaFill;
        private Image healthFill;
        private Text questText;

        private GameObject dialoguePanel;
        private Text dialogueSpeaker;
        private Text dialogueLine;
        private readonly List<Button> dialogueChoiceButtons = new List<Button>();
        private readonly List<Text> dialogueChoiceLabels = new List<Text>();
        private DialogueRunner activeDialogue;

        private Font uiFont;

        private void Awake()
        {
            uiFont = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            BuildCanvas();
        }

        private void Start()
        {
            if (playerSpellCasting != null)
            {
                playerSpellCasting.onManaChanged.AddListener(SetManaFraction);
                SetManaFraction(playerSpellCasting.CurrentMana / Mathf.Max(1f, playerSpellCasting.maxMana));
            }

            if (playerHealth != null)
            {
                playerHealth.onHealthChanged.AddListener(SetHealthFraction);
                SetHealthFraction(playerHealth.CurrentHealth / Mathf.Max(1f, playerHealth.maxHealth));
            }

            if (QuestManager.Instance != null)
            {
                QuestManager.Instance.onQuestStarted.AddListener(_ => RefreshQuestText());
                QuestManager.Instance.onQuestCompleted.AddListener(_ => RefreshQuestText());
                RefreshQuestText();
            }
        }

        private void RefreshQuestText()
        {
            if (QuestManager.Instance == null || questText == null) return;
            string text = QuestManager.Instance.GetCurrentObjectiveText(trackedMainQuestId);
            questText.text = string.IsNullOrEmpty(text) ? string.Empty : "Objective: " + text;
        }

        private void SetManaFraction(float f) { if (manaFill != null) manaFill.fillAmount = Mathf.Clamp01(f); }
        private void SetHealthFraction(float f) { if (healthFill != null) healthFill.fillAmount = Mathf.Clamp01(f); }

        // ---------- Dialogue hookup (called from an NPC interaction script) ----------

        public void ShowDialogue(DialogueRunner runner)
        {
            if (activeDialogue != null) HideDialogue();

            activeDialogue = runner;
            activeDialogue.onLineChanged.AddListener(OnDialogueLineChanged);
            activeDialogue.onDialogueEnded.AddListener(HideDialogue);
            dialoguePanel.SetActive(true);
            activeDialogue.StartDialogue();
        }

        private void HideDialogue()
        {
            if (activeDialogue != null)
            {
                activeDialogue.onLineChanged.RemoveListener(OnDialogueLineChanged);
                activeDialogue.onDialogueEnded.RemoveListener(HideDialogue);
                activeDialogue = null;
            }
            dialoguePanel.SetActive(false);
        }

        private void OnDialogueLineChanged(DialogueLine line)
        {
            dialogueSpeaker.text = line.speakerName;
            dialogueLine.text = line.lineText;

            bool hasChoices = line.choices != null && line.choices.Count > 0;
            for (int i = 0; i < dialogueChoiceButtons.Count; i++)
            {
                bool active = hasChoices && i < line.choices.Count;
                dialogueChoiceButtons[i].gameObject.SetActive(active);
                if (active)
                {
                    dialogueChoiceLabels[i].text = line.choices[i].choiceText;
                    int choiceIndex = i;
                    dialogueChoiceButtons[i].onClick.RemoveAllListeners();
                    dialogueChoiceButtons[i].onClick.AddListener(() => activeDialogue.SelectChoice(choiceIndex));
                }
            }

            // No choices: the first button becomes a single "Continue" prompt.
            if (!hasChoices && dialogueChoiceButtons.Count > 0)
            {
                dialogueChoiceButtons[0].gameObject.SetActive(true);
                dialogueChoiceLabels[0].text = "Continue";
                dialogueChoiceButtons[0].onClick.RemoveAllListeners();
                dialogueChoiceButtons[0].onClick.AddListener(() => activeDialogue.AdvanceWithNoChoice());
            }
        }

        // ---------- Layout construction ----------

        private void BuildCanvas()
        {
            var canvasGO = new GameObject("HUD Canvas (runtime-built)");
            canvasGO.transform.SetParent(transform, false);
            var canvas = canvasGO.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvasGO.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920, 1080);
            canvasGO.AddComponent<GraphicRaycaster>();

            if (FindObjectOfType<EventSystem>() == null)
            {
                var esGO = new GameObject("EventSystem");
                esGO.AddComponent<EventSystem>();
                esGO.AddComponent<StandaloneInputModule>();
            }

            Transform canvasRoot = canvasGO.transform;

            // Quest objective banner, top-left.
            questText = CreateText(canvasRoot, "QuestText", new Vector2(0f, 1f), new Vector2(0f, 1f),
                new Vector2(20f, -20f), new Vector2(700f, 60f), TextAnchor.UpperLeft, 22);

            // Health bar, bottom-left.
            healthFill = CreateBar(canvasRoot, "HealthBar", new Vector2(0f, 0f), new Vector2(0f, 0f),
                new Vector2(20f, 20f), new Vector2(220f, 18f), new Color(0.75f, 0.15f, 0.15f));

            // Mana bar, bottom-left, just above health.
            manaFill = CreateBar(canvasRoot, "ManaBar", new Vector2(0f, 0f), new Vector2(0f, 0f),
                new Vector2(20f, 46f), new Vector2(220f, 18f), new Color(0.2f, 0.55f, 0.85f));

            BuildDialoguePanel(canvasRoot);
        }

        private Text CreateText(Transform parent, string name, Vector2 anchorMin, Vector2 anchorMax,
            Vector2 anchoredPosition, Vector2 size, TextAnchor alignment, int fontSize)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            var rect = go.AddComponent<RectTransform>();
            rect.anchorMin = anchorMin;
            rect.anchorMax = anchorMax;
            rect.pivot = anchorMin;
            rect.anchoredPosition = anchoredPosition;
            rect.sizeDelta = size;

            var text = go.AddComponent<Text>();
            text.font = uiFont;
            text.fontSize = fontSize;
            text.alignment = alignment;
            text.color = Color.white;
            text.horizontalOverflow = HorizontalWrapMode.Wrap;
            return text;
        }

        private Image CreateBar(Transform parent, string name, Vector2 anchorMin, Vector2 anchorMax,
            Vector2 anchoredPosition, Vector2 size, Color fillColor)
        {
            var bgGO = new GameObject(name + "_Background");
            bgGO.transform.SetParent(parent, false);
            var bgRect = bgGO.AddComponent<RectTransform>();
            bgRect.anchorMin = anchorMin;
            bgRect.anchorMax = anchorMax;
            bgRect.pivot = anchorMin;
            bgRect.anchoredPosition = anchoredPosition;
            bgRect.sizeDelta = size;
            var bgImage = bgGO.AddComponent<Image>();
            bgImage.color = new Color(0f, 0f, 0f, 0.5f);

            var fillGO = new GameObject(name + "_Fill");
            fillGO.transform.SetParent(bgGO.transform, false);
            var fillRect = fillGO.AddComponent<RectTransform>();
            fillRect.anchorMin = Vector2.zero;
            fillRect.anchorMax = Vector2.one;
            fillRect.offsetMin = Vector2.zero;
            fillRect.offsetMax = Vector2.zero;
            var fillImage = fillGO.AddComponent<Image>();
            fillImage.color = fillColor;
            fillImage.type = Image.Type.Filled;
            fillImage.fillMethod = Image.FillMethod.Horizontal;
            fillImage.fillAmount = 1f;
            return fillImage;
        }

        private void BuildDialoguePanel(Transform canvasRoot)
        {
            dialoguePanel = new GameObject("DialoguePanel");
            dialoguePanel.transform.SetParent(canvasRoot, false);
            var panelRect = dialoguePanel.AddComponent<RectTransform>();
            panelRect.anchorMin = new Vector2(0.1f, 0f);
            panelRect.anchorMax = new Vector2(0.9f, 0f);
            panelRect.pivot = new Vector2(0.5f, 0f);
            panelRect.anchoredPosition = new Vector2(0f, 30f);
            panelRect.sizeDelta = new Vector2(0f, 220f);
            var panelImage = dialoguePanel.AddComponent<Image>();
            panelImage.color = new Color(0.05f, 0.05f, 0.08f, 0.9f);

            dialogueSpeaker = CreateText(dialoguePanel.transform, "Speaker", new Vector2(0f, 1f), new Vector2(0f, 1f),
                new Vector2(20f, -14f), new Vector2(400f, 30f), TextAnchor.UpperLeft, 20);
            dialogueSpeaker.fontStyle = FontStyle.Bold;

            dialogueLine = CreateText(dialoguePanel.transform, "Line", new Vector2(0f, 1f), new Vector2(1f, 1f),
                new Vector2(20f, -48f), new Vector2(-40f, 90f), TextAnchor.UpperLeft, 18);

            for (int i = 0; i < 4; i++)
            {
                var buttonGO = new GameObject("Choice_" + i);
                buttonGO.transform.SetParent(dialoguePanel.transform, false);
                var buttonRect = buttonGO.AddComponent<RectTransform>();
                buttonRect.anchorMin = new Vector2(0f, 0f);
                buttonRect.anchorMax = new Vector2(0f, 0f);
                buttonRect.pivot = new Vector2(0f, 0f);
                buttonRect.anchoredPosition = new Vector2(20f, 14f + i * 34f);
                buttonRect.sizeDelta = new Vector2(600f, 30f);

                var buttonImage = buttonGO.AddComponent<Image>();
                buttonImage.color = new Color(1f, 1f, 1f, 0.08f);
                var button = buttonGO.AddComponent<Button>();

                var labelText = CreateText(buttonGO.transform, "Label", Vector2.zero, Vector2.one,
                    Vector2.zero, Vector2.zero, TextAnchor.MiddleLeft, 16);
                var labelRect = labelText.GetComponent<RectTransform>();
                labelRect.offsetMin = new Vector2(10f, 0f);
                labelRect.offsetMax = Vector2.zero;

                buttonGO.SetActive(false);
                dialogueChoiceButtons.Add(button);
                dialogueChoiceLabels.Add(labelText);
            }

            dialoguePanel.SetActive(false);
        }
    }
}
