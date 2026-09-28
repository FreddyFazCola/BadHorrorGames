using UnityEngine;

namespace Arcaneum
{
    /// <summary>Simple mouse-orbit chase camera. Attach to the Main Camera and assign target to the player.</summary>
    public class ThirdPersonCamera : MonoBehaviour
    {
        public Transform target;
        public float distance = 5.6f;
        public float height = 1.6f;
        public float mouseSensitivity = 2.5f;
        public float minPitch = -10f;
        public float maxPitch = 55f;
        public float followSmoothing = 10f;

        private float yaw;
        private float pitch = 15f;

        private void Start()
        {
            Cursor.lockState = CursorLockMode.Locked;
            if (target != null) yaw = target.eulerAngles.y;
        }

        private void Update()
        {
            if (Input.GetKeyDown(KeyCode.Escape)) Cursor.lockState = CursorLockMode.None;
            if (Input.GetMouseButtonDown(0) && Cursor.lockState != CursorLockMode.Locked)
                Cursor.lockState = CursorLockMode.Locked;

            if (Cursor.lockState != CursorLockMode.Locked) return;

            yaw += Input.GetAxis("Mouse X") * mouseSensitivity;
            pitch -= Input.GetAxis("Mouse Y") * mouseSensitivity;
            pitch = Mathf.Clamp(pitch, minPitch, maxPitch);
        }

        private void LateUpdate()
        {
            if (target == null) return;

            Quaternion rotation = Quaternion.Euler(pitch, yaw, 0f);
            Vector3 desiredPosition = target.position + Vector3.up * height - rotation * Vector3.forward * distance;
            transform.position = Vector3.Lerp(transform.position, desiredPosition, followSmoothing * Time.deltaTime);
            transform.LookAt(target.position + Vector3.up * height * 0.6f);
        }
    }
}
