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


if __name__ == "__main__":
    unittest.main()
