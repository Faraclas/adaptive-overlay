"""Offline request-header regressions; no credential discovery or HTTP calls."""
import copy
from types import SimpleNamespace
import unittest

from agent.client_lifecycle import ClientLifecycleMixin

CHAT_IMAGE = {"messages": [{"role": "user", "content": [
    {"type": "image_url", "image_url": {"url": "data:image/png;base64,offline"}}
]}]}
RESPONSES_IMAGE = {"input": [{"role": "user", "content": [
    {"type": "input_image", "image_url": "data:image/png;base64,offline"}
]}]}
TEXT = {"messages": [{"role": "user", "content": "offline"}]}


class HeaderProbe(ClientLifecycleMixin):
    """Exercise real request construction/cache, replacing only wire clients."""
    provider = "copilot"
    _request_client_cache: dict

    def __init__(self, headers=None, base_url="https://api.githubcopilot.com"):
        self._client_kwargs = {"api_key": "offline-fixture", "base_url": base_url}
        if headers is not None:
            self._client_kwargs["default_headers"] = headers
        self.created = []
        self.closed = []

    def _ensure_primary_openai_client(self, **kwargs):
        return SimpleNamespace(is_closed=False)

    def _create_openai_client(self, request_kwargs, **kwargs):
        client = SimpleNamespace(kwargs=request_kwargs, is_closed=False)
        self.created.append(client)
        return client

    def _close_openai_client(self, client, **kwargs):
        client.is_closed = True
        self.closed.append(client)

    def request(self, payload):
        return self._create_request_openai_client(reason="offline_test", api_kwargs=payload)

    def release(self, client):
        self._close_request_openai_client(client, reason="request_complete")


def normalized(headers):
    return {name.lower(): value for name, value in headers.items()}


class CopilotImageHeadersTests(unittest.TestCase):
    def test_chat_image_preserves_configured_integration_and_custom_headers(self):
        probe = HeaderProbe({"Copilot-Integration-Id": "copilot-developer-cli",
                             "X-Request-Probe": "preserve-me"})
        client = probe.request(CHAT_IMAGE)
        headers = normalized(client.kwargs["default_headers"])
        self.assertEqual(headers["copilot-integration-id"], "copilot-developer-cli")
        self.assertEqual(headers["x-request-probe"], "preserve-me")
        self.assertEqual(headers["copilot-vision-request"], "true")
        self.assertEqual(client.kwargs["api_key"], "offline-fixture")
        self.assertEqual(client.kwargs["max_retries"], 0)


    def test_responses_image_merges_header_names_case_insensitively(self):
        for integration_name in ("copilot-integration-id", "COPILOT-INTEGRATION-ID"):
            with self.subTest(integration_name=integration_name):
                configured = {integration_name: "copilot-developer-cli",
                              "user-agent": "custom-agent", "X-Request-Probe": "custom"}
                probe = HeaderProbe(configured)
                headers = probe.request(RESPONSES_IMAGE).kwargs["default_headers"]
                names = [name.lower() for name in headers]
                self.assertEqual(len(names), len(set(names)))
                self.assertEqual(normalized(headers)["copilot-integration-id"], "copilot-developer-cli")
                self.assertEqual(normalized(headers)["user-agent"], "custom-agent")
                self.assertEqual(normalized(headers)["x-request-probe"], "custom")
                self.assertEqual(normalized(headers)["copilot-vision-request"], "true")


    def test_vision_flag_is_mandatory_even_if_configured_false(self):
        for name in ("Copilot-Vision-Request", "copilot-vision-request", "COPILOT-VISION-REQUEST"):
            with self.subTest(name=name):
                configured = {name: "false", "Copilot-Integration-Id": "copilot-developer-cli"}
                probe = HeaderProbe(configured)
                headers = probe.request(RESPONSES_IMAGE).kwargs["default_headers"]
                self.assertEqual(normalized(headers)["copilot-vision-request"], "true")
                self.assertEqual(configured[name], "false")
                self.assertEqual(sum(key.lower() == "copilot-vision-request" for key in headers), 1)


    def test_oauth_defaults_unchanged_when_no_headers_are_configured(self):
        from hermes_cli.copilot_auth import copilot_request_headers
        for configured in (None, {}):
            with self.subTest(configured=configured):
                probe = HeaderProbe(configured)
                headers = probe.request(CHAT_IMAGE).kwargs["default_headers"]
                self.assertEqual(headers, copilot_request_headers(is_agent_turn=True, is_vision=True))
                self.assertEqual(headers["Copilot-Integration-Id"], "vscode-chat")

    def test_existing_oauth_headers_remain_effective(self):
        from hermes_cli.copilot_auth import copilot_request_headers
        configured = copilot_request_headers(is_agent_turn=False)
        probe = HeaderProbe(configured)
        expected = dict(configured, **{"Copilot-Vision-Request": "true"})
        self.assertEqual(probe.request(RESPONSES_IMAGE).kwargs["default_headers"], expected)
        self.assertNotIn("Copilot-Vision-Request", configured)

    def test_non_copilot_images_do_not_change_headers(self):
        for base_url in ("https://api.openai.com/v1", "https://githubcopilot.com.example.invalid"):
            for payload in (CHAT_IMAGE, RESPONSES_IMAGE):
                with self.subTest(base_url=base_url, payload=payload):
                    configured = {"Copilot-Integration-Id": "custom", "Copilot-Vision-Request": "false"}
                    probe = HeaderProbe(configured, base_url=base_url)
                    probe.provider = "openai"
                    self.assertEqual(probe.request(payload).kwargs["default_headers"], configured)
                    self.assertEqual(configured["Copilot-Vision-Request"], "false")
        probe = HeaderProbe(base_url="https://api.openai.com/v1")
        self.assertNotIn("default_headers", probe.request(CHAT_IMAGE).kwargs)

    def test_image_headers_do_not_mutate_config_or_request_cache_key(self):
        configured = {"copilot-integration-id": "copilot-developer-cli", "X-Request-Probe": "before"}
        probe = HeaderProbe(configured)
        original = copy.deepcopy(probe._client_kwargs)
        client = probe.request(CHAT_IMAGE)
        self.assertEqual(probe._client_kwargs, original)
        key = copy.deepcopy(probe._request_client_cache["key"])
        client.kwargs["default_headers"]["X-Request-Probe"] = "client-only"
        configured["X-Request-Probe"] = "config-only"
        self.assertEqual(probe._request_client_cache["key"], key)
        self.assertEqual(key["default_headers"]["X-Request-Probe"], "before")
        self.assertEqual(key["default_headers"]["Copilot-Vision-Request"], "true")
        probe.release(client)
        replacement = probe.request(CHAT_IMAGE)
        self.assertIsNot(replacement, client)
        self.assertEqual(replacement.kwargs["default_headers"]["X-Request-Probe"], "config-only")

    def test_text_image_text_reuses_only_matching_request_clients(self):
        for image in (CHAT_IMAGE, RESPONSES_IMAGE):
            with self.subTest(image=image):
                configured = {"Copilot-Integration-Id": "copilot-developer-cli", "X-Request-Probe": "keep"}
                probe = HeaderProbe(configured)
                original = copy.deepcopy(probe._client_kwargs)
                clients = []
                for payload in (TEXT, image, TEXT):
                    client = probe.request(payload)
                    clients.append(client)
                    probe.release(client)
                    reused = probe.request(payload)
                    self.assertIs(reused, client)
                    probe.release(reused)
                    self.assertEqual(probe._client_kwargs, original)
                self.assertEqual(len(probe.created), 3)
                self.assertEqual(probe.closed, clients[:2])
                self.assertIsNot(clients[0], clients[1])
                self.assertIsNot(clients[1], clients[2])
                self.assertEqual(clients[0].kwargs["default_headers"], configured)
                self.assertEqual(clients[2].kwargs["default_headers"], configured)
                self.assertEqual(clients[1].kwargs["default_headers"]["Copilot-Vision-Request"], "true")
                self.assertEqual(clients[1].kwargs["default_headers"]["X-Request-Probe"], "keep")
                self.assertNotIn("Copilot-Vision-Request", clients[2].kwargs["default_headers"])


if __name__ == "__main__":
    unittest.main()
