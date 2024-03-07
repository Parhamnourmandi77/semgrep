import pytest
from tests.fixtures import RunSemgrep


# https://github.com/returntocorp/semgrep/pull/8510
@pytest.mark.kinda_slow
def test_metavariable_regex_const_prop(run_semgrep_in_tmp: RunSemgrep, snapshot):
    snapshot.assert_match(
        run_semgrep_in_tmp(
            "rules/metavariable-regex-const-prop.yaml",
            target_name="metavariable_propagation/metavariable-regex-const-prop.dockerfile",
        ).stdout,
        "results.json",
    )