"""Original care-call intake workflow informed by rural-health-ai's design.

This executes deterministic coordination rules, not the upstream Flutter app,
clinical engine, or TFLite artifacts. See upstream/rural-health-ai/README.md.
"""

from __future__ import annotations

import re

from .base import ProviderConfig, ProviderError


_APPOINTMENT = re.compile(
    r"\bappointments?\b|\b(?:book|schedule|reschedule)\s+(?:a|an|my|the)\b",
    re.IGNORECASE,
)
_CANCEL = re.compile(r"\bcancel(?:led|ling|ing|lation)?\b", re.IGNORECASE)
_WHEN = re.compile(
    r"\b(?:today|tomorrow|morning|afternoon|evening|monday|tuesday|wednesday|"
    r"thursday|friday|saturday|sunday|next week)\b|\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b|"
    r"\b\d{4}-\d{2}-\d{2}\b",
    re.IGNORECASE,
)
_DIAGNOSIS = re.compile(
    r"\b(?:diagnos\w*|prescrib\w*|dosage|dose|treatment)\b|"
    r"\b(?:do i have|what disease|which disease|what condition|which condition)\b",
    re.IGNORECASE,
)
_OPENING = re.compile(r"generate the opening message|generate my opening|\[venture outbound call\]", re.I)


def _call_goal(request: str) -> str:
    labeled = re.search(r"(?:requested goal|call goal|goal)\s*:\s*([^\n]+)", request, re.I)
    goal = labeled.group(1) if labeled else request
    # The native demo puts its instruction after the goal in one sentence;
    # spoken coordination should carry the goal, without reciting that suffix.
    goal = re.split(r"\.\s+Explain unknown information\b", goal, maxsplit=1, flags=re.I)[0]
    return _excerpt(goal, limit=240)


def _outbound_context(context: str) -> str:
    evidence = _excerpt(context, limit=700)
    return (f"the user's supplied screening evidence is: “{evidence}”. "
            if evidence else "no measured screening evidence was supplied. ")


def _excerpt(value: str, limit: int = 360) -> str:
    """Keep evidence attributed, bounded, and free of terminal control bytes."""
    cleaned = re.sub(r"\s+", " ", re.sub(r"[\x00-\x1f\x7f]", " ", value)).strip()
    return cleaned if len(cleaned) <= limit else cleaned[: limit - 1].rstrip() + "…"


class RuralHealthAIProvider:
    id = "rural-health-ai"
    name = "rural health ai"
    kind = "rules adaptation (no TFLite inference)"
    model = "deterministic care workflow"
    configured = True
    unavailable_reason = ""

    def __init__(self, config: ProviderConfig) -> None:
        self.config = config

    async def complete(
        self,
        messages: list[dict[str, str]],
        language: str,
        context: str = "",
    ) -> str:
        """Prepare an English care handoff without booking, calling, or diagnosis.

        Only caller turns contribute intent. Context is supplied screening
        evidence; it is never converted to diagnoses, risk tiers, or invented
        measurements. There is no retained provider conversation state.
        """
        language_code = language.strip().lower().replace("_", "-")
        if language_code != "en" and not language_code.startswith("en-"):
            raise ProviderError(
                "rural health ai's rules adaptation currently supports English only",
                status_code=422,
            )

        caller_turns = [
            message["content"].strip()
            for message in messages
            if message.get("role") == "user"
            and isinstance(message.get("content"), str)
            and message["content"].strip()
        ]
        if not caller_turns:
            return (
                "i can help prepare a care call or appointment request. "
                "what would you like to discuss with your care team?"
            )

        current_request = caller_turns[-1]
        opening_request = next((turn for turn in caller_turns if _OPENING.search(turn)), "")
        if opening_request:
            goal = _call_goal(opening_request)
            if current_request == opening_request:
                return (
                    "this is Venture's automated care assistant, calling with the user's permission. "
                    f"the requested goal is: “{goal}”. " + _outbound_context(context)
                    + "these findings are screening context, not a diagnosis. "
                    "what is the process for arranging an appropriate routine appointment, "
                    "and what information does the user need to provide directly?"
                )
            if re.search(r"\b(?:name|birth|dob|insurance|address)\b", current_request, re.I):
                return (
                    "i do not have those personal details or authority to confirm them. "
                    "the user will need to provide them directly through the clinic's process. "
                    "how should they complete that step?"
                )
            if re.search(r"\b(?:time|date|day|available|availability)\b", current_request, re.I):
                return (
                    "the user needs to confirm a preferred time directly. "
                    "what routine appointment options or booking process can they review?"
                )
            return (
                f"i am coordinating the user's request: “{goal}”. " + _outbound_context(context)
                + "these are supplied screening findings, not a diagnosis. "
                "please explain the next appointment step for the user to confirm directly."
            )
        if _DIAGNOSIS.search(current_request):
            return (
                "i can help explain supplied screening evidence and prepare questions "
                "for your care team. a clinician needs to assess diagnoses and "
                "treatment. what finding or concern would you like to share with them?"
            )

        # A short answer such as "tomorrow afternoon" carries the prior caller's
        # appointment intent. Assistant/system turns never supply request facts.
        appointment_indices = [
            index for index, turn in enumerate(caller_turns) if _APPOINTMENT.search(turn)
        ]
        appointment_followup = bool(
            _WHEN.search(current_request)
            or _CANCEL.search(current_request)
            or current_request.casefold() in {"yes", "yes please", "no", "ok", "okay", "that works"}
        )
        if _APPOINTMENT.search(current_request) or (appointment_indices and appointment_followup):
            recent_turns = caller_turns[appointment_indices[-1] :]
            if _CANCEL.search(current_request):
                return (
                    "i can help prepare a cancellation request. which clinic and "
                    "appointment date should it refer to? the clinic will need to "
                    "confirm the cancellation."
                )
            if not any(_WHEN.search(turn) for turn in recent_turns):
                return (
                    "i can help prepare an appointment request. which clinic or "
                    "care team should receive it, and what day and time do you prefer? "
                    "availability needs confirmation from the clinic."
                )
            timing_turn = next(turn for turn in reversed(recent_turns) if _WHEN.search(turn))
            return (
                f"for the appointment request, you mentioned: “{_excerpt(timing_turn)}”. "
                "please confirm the care team, your preferred day and time, and the "
                "reason for the visit with the clinic. they need to confirm availability "
                "and the booking."
            )

        reported = _excerpt(current_request)
        supplied_evidence = _excerpt(context, limit=700)
        if supplied_evidence:
            return (
                f"you reported: “{reported}”. "
                f"the supplied screening context says: “{supplied_evidence}”. "
                "this is screening context; it does not establish a diagnosis. "
                "next action: share this concern and the measured findings with "
                "your care team. what question would you like to ask them?"
            )

        return (
            f"you reported: “{reported}”. "
            "no measured screening evidence was supplied for this request. "
            "next action: share your concern with your care team and ask what "
            "assessment is appropriate. do you have a measured finding you want "
            "to include in that conversation?"
        )
