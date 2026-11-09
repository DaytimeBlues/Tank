"""Static CPU/source guards only, not GDScript or engine execution."""
from pathlib import Path
import importlib.util
import json
import unittest

ROOT = Path(__file__).resolve().parents[1]
loader=importlib.util.spec_from_file_location('wire_scope',ROOT/'tools/check-wire-contact-fix.py')
scope=importlib.util.module_from_spec(loader)
loader.loader.exec_module(scope)


class TypedPredicate(unittest.TestCase):
    def test_contact_gate_is_explicit_and_has_no_bool_variant_cast(self):
        source = (ROOT/'scripts/shot_effects.gd').read_text()
        self.assertTrue('var contact: bool = (hit is String and not hit.is_empty()) or (hit is bool and hit == true) or (blocked is bool and blocked == true)' in source,
                        'Explicit String/legacy-Boolean/blocked-Boolean predicate absent')
        self.assertFalse('bool(shot.get("hit"' in source)


class ExactScope(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original=scope.baseline()
        cls.actual=scope.snapshot()
        cls.spec=json.loads((ROOT/scope.MANIFEST).read_text())

    def reject(self,name,change):
        altered=dict(self.actual);altered[name]=change(altered[name])
        with self.assertRaises(AssertionError):scope.validate(altered,self.original,self.spec)

    def test_complete_exact_baseline_packet(self):
        report=scope.validate(self.actual,self.original,self.spec)
        self.assertTrue(report['authorityBridge46Exact'] and report['allOriginalTestsAndShaderExact'])

    def test_original_bool_constructor_reintroduction_rejects(self):
        self.reject('scripts/shot_effects.gd',lambda _:self.original['scripts/shot_effects.gd'])

    def test_unsupported_blocked_truthiness_rejects(self):
        self.reject('scripts/shot_effects.gd',lambda b:b.replace(b'(blocked is bool and blocked == true)',b'blocked'))

    def test_legacy_boolean_support_removal_rejects(self):
        self.reject('scripts/shot_effects.gd',lambda b:b.replace(b' or (hit is bool and hit == true)',b''))

    def test_shader_change_rejects(self):
        self.reject('assets/effects/accepted_shot.gdshader',lambda b:b+b'\n// style change\n')

    def test_authority_change_rejects(self):
        self.reject('backend/src/battle-room.mjs',lambda b:b+b'\n// unexpected\n')

    def test_history_or_old_assertion_changes_reject(self):
        self.reject('scripts/main.gd',lambda b:b+b'\n# unexpected\n')
        self.reject('tests/visual_effects.gd',lambda b:b+b'\n# weakened historical test\n')

    def test_missing_wire_fixture_or_extra_runtime_file_reject(self):
        altered=dict(self.actual);altered.pop('tests/wire_contact_types.gd')
        with self.assertRaises(AssertionError):scope.validate(altered,self.original,self.spec)
        altered=dict(self.actual);altered['scripts/unapproved.gd']=b'extends Node\n'
        with self.assertRaises(AssertionError):scope.validate(altered,self.original,self.spec)

    def test_prospective_fixture_guards_missing_contact_and_finishes(self):
        source=self.actual['tests/wire_contact_types.gd'].decode()
        self.assertIn('if found.size() == 1:\n\t\tvar slot: Dictionary = found[0]',source)
        self.assertNotIn('contacts(fx)[0]',source)
        self.assertIn('finish(main,"type_matrix")\n\t\t\t\treturn',source)
        self.assertIn('print("TANK_WIRE_CONTACT_TYPES "+JSON.stringify(report))',source)
        self.assertIn('quit(0 if failures.is_empty() else 1)',source)


if __name__ == '__main__':
    unittest.main(verbosity=2)
