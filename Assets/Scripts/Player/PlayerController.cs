using UnityEngine;

namespace Arcaneum
{
    /// <summary>
    /// Base player movement/casting-input. Mesh, animation, and VFX are assigned on a
    /// prefab variant once licensed art/animation packs are imported -- see root README.md.
    /// Uses Unity's legacy Input Manager (Input.GetAxis/GetButtonDown) rather than the newer
    /// Input System package, to keep this scaffold dependency-free out of the box.
    /// </summary>
    [RequireComponent(typeof(CharacterController))]
    [RequireComponent(typeof(SpellCasting))]
    public class PlayerController : MonoBehaviour
    {
        [Header("Movement")]
        public float moveSpeed = 4.5f;
        public float turnSmoothing = 10f;
        public float gravity = -20f;
        public float jumpHeight = 1.2f;

        [Header("Equipped spells (index 0 = primary / left-click, 1 = secondary / right-click)")]
        public SpellDefinition[] equippedSpells = new SpellDefinition[2];

        private CharacterController controller;
        private SpellCasting spellCasting;
        private Transform cameraTransform;
        private float verticalVelocity;

        private void Awake()
        {
            controller = GetComponent<CharacterController>();
            spellCasting = GetComponent<SpellCasting>();
            if (Camera.main != null) cameraTransform = Camera.main.transform;
        }

        private void Update()
        {
            HandleMovement();
            HandleCasting();
        }

        private void HandleMovement()
        {
            float h = Input.GetAxis("Horizontal");
            float v = Input.GetAxis("Vertical");
            Vector3 inputDir = new Vector3(h, 0f, v);
            if (inputDir.sqrMagnitude > 1f) inputDir.Normalize();

            if (controller.isGrounded && verticalVelocity < 0f) verticalVelocity = -2f;
            if (controller.isGrounded && Input.GetButtonDown("Jump"))
                verticalVelocity = Mathf.Sqrt(jumpHeight * -2f * gravity);
            verticalVelocity += gravity * Time.deltaTime;

            if (inputDir.magnitude >= 0.1f)
            {
                float camYaw = cameraTransform != null ? cameraTransform.eulerAngles.y : 0f;
                float targetAngle = Mathf.Atan2(inputDir.x, inputDir.z) * Mathf.Rad2Deg + camYaw;
                float angle = Mathf.LerpAngle(transform.eulerAngles.y, targetAngle, turnSmoothing * Time.deltaTime);
                transform.rotation = Quaternion.Euler(0f, angle, 0f);

                Vector3 moveDir = Quaternion.Euler(0f, targetAngle, 0f) * Vector3.forward;
                controller.Move(moveDir.normalized * moveSpeed * Time.deltaTime);
            }

            controller.Move(Vector3.up * verticalVelocity * Time.deltaTime);
        }

        private void HandleCasting()
        {
            if (Input.GetMouseButtonDown(0) || Input.GetKeyDown(KeyCode.F))
                CastEquipped(0);
            if (Input.GetMouseButtonDown(1))
                CastEquipped(1);
        }

        private void CastEquipped(int slot)
        {
            if (slot < 0 || slot >= equippedSpells.Length || equippedSpells[slot] == null) return;
            spellCasting.TryCastSpell(equippedSpells[slot]);
        }
    }
}
