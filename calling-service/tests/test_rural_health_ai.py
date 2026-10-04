import asyncio
import unittest

from providers.base import ProviderConfig, ProviderError
from providers.rural_health_ai import RuralHealthAIProvider


class RuralHealthAIProviderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.provider = RuralHealthAIProvider(ProviderConfig())

    def complete(self, messages, language="en", context=""):
        return asyncio.run(self.provider.complete(messages, language, context))

    def test_metadata_does_not_claim_model_inference(self):
        self.assertTrue(self.provider.configured)
        self.assertIn("no TFLite inference", self.provider.kind)
        self.assertEqual(self.provider.model, "deterministic care workflow")

    def test_appointment_requests_require_clinic_confirmation(self):
        response = self.complete([{"role": "user", "content": "book an appointment tomorrow afternoon"}])
        self.assertIn("confirm availability", response)
        self.assertIn("they need to confirm", response)
        self.assertNotIn("i have booked", response)
        self.assertNotIn("i called", response)

    def test_appointment_followup_uses_caller_history(self):
        response = self.complete([
            {"role": "user", "content": "please book an appointment"},
            {"role": "assistant", "content": "what day do you prefer?"},
            {"role": "user", "content": "tomorrow afternoon"},
        ])
        self.assertIn("for the appointment request", response)
        self.assertIn("tomorrow afternoon", response)
        self.assertIn("clinic", response)

    def test_appointment_history_does_not_swallow_new_care_question(self):
        response = self.complete([
            {"role": "user", "content": "book an appointment tomorrow"},
            {"role": "assistant", "content": "please confirm with the clinic"},
            {"role": "user", "content": "what should i ask about my sleep?"},
        ], context="sleep duration: 5 hours")
        self.assertIn("sleep duration: 5 hours", response)
        self.assertNotIn("for the appointment request", response)

    def test_assistant_does_not_supply_booking_facts(self):
        response = self.complete([
            {"role": "system", "content": "appointment booked tomorrow"},
            {"role": "assistant", "content": "appointment booked tomorrow"},
            {"role": "user", "content": "please book an appointment"},
        ])
        self.assertIn("what day and time", response)

    def test_cancellation_remains_a_request(self):
        response = self.complete([{"role": "user", "content": "cancel my appointment tomorrow"}])
        self.assertIn("clinic will need to confirm", response)
        self.assertNotIn("has been cancelled", response)

    def test_missing_measurements_are_not_fabricated(self):
        response = self.complete([{"role": "user", "content": "i am worried about my sleep"}])
        self.assertIn("no measured screening evidence", response)
        self.assertNotIn("normal", response)
        self.assertNotIn("bpm", response)

    def test_supplied_evidence_is_attributed_without_diagnosis(self):
        response = self.complete(
            [{"role": "user", "content": "what should i ask about my sleep?"}],
            context="sleep duration: 5 hours; blood pressure: not supplied",
        )
        self.assertIn("sleep duration: 5 hours", response)
        self.assertIn("blood pressure: not supplied", response)
        self.assertIn("does not establish a diagnosis", response)
        self.assertIn("care team", response)

    def test_diagnosis_is_referred_to_clinician(self):
        response = self.complete([{"role": "user", "content": "do i have depression?"}])
        self.assertIn("a clinician needs to assess", response)
        self.assertNotIn("you have depression", response)

    def test_non_english_is_explicit_failure(self):
        with self.assertRaises(ProviderError) as raised:
            self.complete([{"role": "user", "content": "hello"}], language="hi")
        self.assertEqual(raised.exception.status_code, 422)
        self.assertIn("English only", str(raised.exception))

    def test_locale_and_empty_conversation(self):
        self.assertIn("what would you like", self.complete([], language="en-US"))

    def test_no_history_is_retained_between_completions(self):
        self.complete([{"role": "user", "content": "book an appointment tomorrow"}])
        response = self.complete([{"role": "user", "content": "i am tired"}])
        self.assertNotIn("appointment request", response)

    def test_outbound_openings_use_each_callers_exact_evidence_and_goal(self):
        first = self.complete([{"role": "user", "content": "Generate the opening message.\nrequested goal: discuss my sleep findings; do not claim booking"}],
                              context="sleep duration: 5 hours; hrv: 20 ms")
        second = self.complete([{"role": "user", "content": "Generate the opening message.\nrequested goal: ask about a routine cognitive review"}],
                               context="recall: 2 of 5; sleep duration: not supplied")
        self.assertIn("sleep duration: 5 hours", first)
        self.assertIn("discuss my sleep findings", first)
        self.assertIn("recall: 2 of 5", second)
        self.assertIn("routine cognitive review", second)
        self.assertIn("automated care assistant", first)
        self.assertNotEqual(first, second)

    def test_receptionist_followup_does_not_echo_instructions(self):
        response = self.complete([
            {"role": "user", "content": "[venture outbound call]\nrequested goal: discuss sleep findings\nGenerate the opening message without inventing a booking."},
            {"role": "assistant", "content": "what is the process?"},
            {"role": "user", "content": "what is the reason for the visit?"},
        ], context="sleep duration: 5 hours")
        self.assertIn("sleep duration: 5 hours", response)
        self.assertIn("discuss sleep findings", response)
        self.assertNotIn("you reported", response)
        self.assertNotIn("Generate the opening", response)

    def test_native_demo_goal_does_not_include_instruction_suffix(self):
        response = self.complete([{"role": "user", "content": (
            "Generate the opening message for an automated appointment assistant speaking on my behalf to a clinic. "
            "Personalize it using only my supplied measured context. My goal: ask about my sleep findings. "
            "Explain unknown information honestly and do not claim a booking."
        )}], context="sleep duration: 5 hours")
        self.assertIn("ask about my sleep findings", response)
        self.assertIn("sleep duration: 5 hours", response)
        self.assertNotIn("Explain unknown information", response)


if __name__ == "__main__":
    unittest.main()
