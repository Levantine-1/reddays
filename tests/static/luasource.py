"""Shared Lua source preprocessing for the static checks."""

import re

_LONG_COMMENT = re.compile(r"--\[(=*)\[.*?\]\1\]", re.DOTALL)
_LINE_COMMENT = re.compile(r"--[^\n]*")
_LONG_STRING = re.compile(r"\[(=*)\[.*?\]\1\]", re.DOTALL)
_DQ_STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')
_SQ_STRING = re.compile(r"'(?:[^'\\\n]|\\.)*'")


def strip_comments(text):
    """Remove Lua comments, preserving line structure where cheap."""
    text = _LONG_COMMENT.sub("", text)
    return _LINE_COMMENT.sub("", text)


def strip_comments_and_strings(text):
    """Remove comments AND string literals.

    Needed before scanning for call sites: a log line like
    print("obese (" .. n) otherwise looks exactly like a call to obese().
    """
    text = strip_comments(text)
    text = _LONG_STRING.sub('""', text)
    text = _DQ_STRING.sub('""', text)
    return _SQ_STRING.sub("''", text)
