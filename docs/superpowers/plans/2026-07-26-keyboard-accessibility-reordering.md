# Keyboard-Accessible Reordering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable keyboard/VoiceOver reordering in `SettingsView.swift` via `.accessibilityAction`.

**Architecture:** Attach `.accessibilityAction(named:)` modifiers to Menu Bar rows and Panel cards in `SettingsView.swift`.

**Tech Stack:** Swift 5.9+, SwiftUI.

## Global Constraints
- Must enforce array boundary guards before swapping.
- Must preserve existing drag-and-drop behavior intact.

---

### Task 1: Add Accessibility Actions to Menu Bar Tab

**Files:**
- Modify: `Sources/PerformanceApp/SettingsView.swift:290-306`

- [ ] **Step 1: Add `.accessibilityAction` for Move Up and Move Down in `MenuBarTab`**

Attach `.accessibilityAction(named: Text(String(localized: "Move Up")))` and `.accessibilityAction(named: Text(String(localized: "Move Down")))` to the Menu Bar row container.

---

### Task 2: Add Accessibility Actions to Panels Tab

**Files:**
- Modify: `Sources/PerformanceApp/SettingsView.swift:980-1028`

- [ ] **Step 2: Add `.accessibilityAction` for Move Earlier and Move Later in `PanelMiniCard`**

Attach `.accessibilityAction(named: Text(String(localized: "Move Earlier")))` and `.accessibilityAction(named: Text(String(localized: "Move Later")))` to `PanelMiniCard`.

- [ ] **Step 3: Commit changes**

```bash
git add Sources/PerformanceApp/SettingsView.swift
git commit -m "Feat: make drag-reordering in Settings keyboard-accessible (#3)"
```
