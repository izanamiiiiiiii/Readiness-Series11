#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parent
sources = ['Engine/RobustReadinessEngine.swift', 'Engine/NightQuality.swift', 'Engine/SafeRRAccumulator.swift', 'Engine/ReadinessStorageCoordinator.swift', 'FitnessAdapter/Sources/FitnessActivityEvaluator.swift', 'Tests/RegressionChecks.swift', 'Tests/FitnessChecks.swift', 'Tests/ModelChecks.swift']
text = (root/'SimulatorHarness/HarnessTemplate.swift.txt').read_text()
for relative in sources:
    text += '\n' + (root/relative).read_text()
(root/'SimulatorHarness/ExperimentalHarnessApp.swift').write_text(text)
