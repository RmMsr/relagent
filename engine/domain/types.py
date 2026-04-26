from enum import Enum


class ApprovalType(Enum):
    NoneRequired = "none"
    OutgoingData = "data/out"


class SensitivityLevel(Enum):
    """Sensitivity classification of information exchanged in a session.

    Each level carries an integer value (used for ordering and serialisation)
    and a human-readable description accessible via the ``description`` property.
    """

    OpenInformation = (
        1,
        "Public information. No strong personal relevance, information could be related to anyone",
    )
    Specific = (
        2,
        "Information is relevant to a group, but does not include personally identifiable information",
    )
    Personal = (3, "May contain information identifying one person")
    Confidential = (4, "Clearly sensitive information")
    Internal = (5, "Data not meant to be shared")

    def __new__(cls, value: int, description: str = "") -> "SensitivityLevel":
        obj = object.__new__(cls)
        obj._value_ = value
        obj.description = description  # type: ignore[attr-defined]
        return obj


class Role(Enum):
    User = "user"
    Assistant = "assistant"
    System = "system"
