import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/catalog/build-plan.py"
EXAMPLES = ROOT / "catalog/examples"


class BuildPlanTest(unittest.TestCase):
    def run_plan(self, plan: pathlib.Path):
        return subprocess.run(
            ["python3", str(SCRIPT), str(plan)], text=True, capture_output=True, check=False
        )

    def test_example_plan_is_deterministic_and_complete(self):
        first = self.run_plan(EXAMPLES / "registration-plan.json")
        second = self.run_plan(EXAMPLES / "registration-plan.json")

        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, second.stdout)
        result = json.loads(first.stdout)
        self.assertEqual(len(result["models"]), 1)
        self.assertEqual(len(result["recipes"]), 1)
        self.assertTrue(result["models"][0]["calldata"].startswith("0x"))
        self.assertNotIn("--data", result["models"][0]["ledger_command"])
        self.assertIn("--from $CATALOG_REGISTRAR", result["models"][0]["ledger_command"])
        self.assertIn("--chain 8453", result["models"][0]["ledger_command"])
        self.assertEqual(
            result["recipes"][0]["required_model_ids"],
            [result["models"][0]["model_id"]],
        )

    def test_recipe_worker_names_must_match_model_manifests(self):
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory)
            for source in EXAMPLES.iterdir():
                shutil.copy(source, target / source.name)
            recipe_path = target / "example-recipe.json"
            recipe = json.loads(recipe_path.read_text())
            recipe["_grid"]["requiredModels"] = ["different-worker-model"]
            recipe_path.write_text(json.dumps(recipe), encoding="utf-8")

            completed = self.run_plan(target / "registration-plan.json")

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("requiredModels must equal manifest worker names", completed.stderr)

    def test_duplicate_json_keys_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            plan = pathlib.Path(directory) / "plan.json"
            plan.write_text('{"publisher":"a","publisher":"b"}', encoding="utf-8")

            completed = self.run_plan(plan)

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("duplicate JSON key", completed.stderr)

    def test_unknown_manifest_fields_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory)
            for source in EXAMPLES.iterdir():
                shutil.copy(source, target / source.name)
            manifest_path = target / "model-manifest.json"
            manifest = json.loads(manifest_path.read_text())
            manifest["min_vram_mb"] = manifest["min_vram_mib"]
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            completed = self.run_plan(target / "registration-plan.json")

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("unknown=['min_vram_mb']", completed.stderr)

    def test_recipe_output_must_include_grid_job_type(self):
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory)
            for source in EXAMPLES.iterdir():
                shutil.copy(source, target / source.name)
            plan_path = target / "registration-plan.json"
            plan = json.loads(plan_path.read_text())
            plan["recipes"][0]["output_modalities"] = ["audio"]
            plan_path.write_text(json.dumps(plan), encoding="utf-8")
            recipe_path = target / "example-recipe.json"
            recipe = json.loads(recipe_path.read_text())
            recipe["_grid"]["catalog"]["outputModalities"] = ["audio"]
            recipe_path.write_text(json.dumps(recipe), encoding="utf-8")

            completed = self.run_plan(plan_path)

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("must include _grid.jobType", completed.stderr)

    def test_mutable_registration_uri_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory)
            for source in EXAMPLES.iterdir():
                shutil.copy(source, target / source.name)
            plan_path = target / "registration-plan.json"
            plan = json.loads(plan_path.read_text())
            plan["models"][0]["manifest_uri"] = "https://example.com/model.json"
            plan_path.write_text(json.dumps(plan), encoding="utf-8")

            completed = self.run_plan(plan_path)

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("must use immutable ipfs:// or ar://", completed.stderr)

    def test_non_base_chain_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory)
            for source in EXAMPLES.iterdir():
                shutil.copy(source, target / source.name)
            plan_path = target / "registration-plan.json"
            plan = json.loads(plan_path.read_text())
            plan["chain_id"] = 1
            plan_path.write_text(json.dumps(plan), encoding="utf-8")

            completed = self.run_plan(plan_path)

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("must be Base mainnet", completed.stderr)

    def test_recipe_catalog_metadata_must_match_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory)
            for source in EXAMPLES.iterdir():
                shutil.copy(source, target / source.name)
            recipe_path = target / "example-recipe.json"
            recipe = json.loads(recipe_path.read_text())
            recipe["_grid"]["catalog"]["version"] = "2.0.0"
            recipe_path.write_text(json.dumps(recipe), encoding="utf-8")

            completed = self.run_plan(target / "registration-plan.json")

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("catalog release must match", completed.stderr)

    def test_recipe_id_uses_rfc8785_number_serialization(self):
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory)
            for source in EXAMPLES.iterdir():
                shutil.copy(source, target / source.name)
            recipe_path = target / "example-recipe.json"
            recipe = json.loads(recipe_path.read_text())
            recipe["_grid"]["numberFixture"] = {
                "tiny": 1e-7,
                "negativeZero": -0.0,
                "one": 1.0,
            }
            recipe_path.write_text(json.dumps(recipe), encoding="utf-8")

            completed = self.run_plan(target / "registration-plan.json")
            canonical = subprocess.run(
                ["node", str(SCRIPT.with_name("canonicalize.mjs")), str(recipe_path)],
                capture_output=True,
                check=True,
            ).stdout

        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(completed.stdout)
        self.assertEqual(
            result["recipes"][0]["recipe_id"],
            "0x" + hashlib.sha256(canonical).hexdigest(),
        )
        self.assertIn(b'"negativeZero":0', canonical)
        self.assertIn(b'"one":1', canonical)
        self.assertIn(b'"tiny":1e-7', canonical)

    def test_canonicalizer_matches_rfc8785_number_vector(self):
        source = (
            '{"numbers":[333333333.33333329,1E30,4.50,2e-3,'
            '0.000000000000000000000000001],"literals":[null,true,false]}'
        )
        expected = (
            b'{"literals":[null,true,false],"numbers":'
            b"[333333333.3333333,1e+30,4.5,0.002,1e-27]}"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "vector.json"
            path.write_text(source, encoding="utf-8")
            canonical = subprocess.run(
                ["node", str(SCRIPT.with_name("canonicalize.mjs")), str(path)],
                capture_output=True,
                check=True,
            ).stdout

        self.assertEqual(canonical, expected)


if __name__ == "__main__":
    unittest.main()
