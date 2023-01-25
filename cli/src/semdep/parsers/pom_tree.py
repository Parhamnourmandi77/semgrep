from pathlib import Path
from typing import List
from typing import Optional

from parsy import string
from parsy import success

from semdep.parsers.util import consume_line
from semdep.parsers.util import mark_line
from semdep.parsers.util import safe_path_parse
from semdep.parsers.util import upto
from semgrep.semgrep_interfaces.semgrep_output_v1 import Direct
from semgrep.semgrep_interfaces.semgrep_output_v1 import Ecosystem
from semgrep.semgrep_interfaces.semgrep_output_v1 import FoundDependency
from semgrep.semgrep_interfaces.semgrep_output_v1 import Maven
from semgrep.semgrep_interfaces.semgrep_output_v1 import Transitive
from semgrep.semgrep_interfaces.semgrep_output_v1 import Transitivity

# Examples:
# org.apache.logging.log4j:log4j-api:jar:0.0.2:compile
dep = upto(":", consume_other=True) >> upto(":", consume_other=True).bind(
    lambda package: upto(":", consume_other=True)
    >> upto(":", consume_other=True).bind(
        lambda version: success((package, version)) << consume_line
    )
)

# Examples (these would not appear in this order in a file, they're seperate):
# |  +- org.apache.maven:maven-model:jar:3.8.6:provided

# |  |  \- org.codehaus.plexus:plexus-component-annotations:jar:1.5.5:provided

# +- org.apache.logging.log4j:log4j-api:jar:0.0.2:compile

#    \- net.java.dev.jna:jna:jar:5.11.0:compile

# |     +- org.springframework:spring-aop:jar:5.3.9:compile
tree_line = mark_line(
    ((string("|  ") | string("   ")).at_least(1) | success([])).bind(
        lambda depth: (string("+- ") | string(r"\- "))
        >> dep.map(
            lambda d: (
                Transitivity(Transitive() if len(depth) > 0 else Direct()),
                d[0],
                d[1],
            )
        )
    )
)


pom_tree = (
    consume_line  # First line is the name of the current project, ignore it
    >> string("\n")
    >> tree_line.sep_by(string("\n"))
    << string("\n").optional()
)


def parse_pom_tree(tree_path: Path, _: Optional[Path]) -> List[FoundDependency]:
    deps = safe_path_parse(tree_path, pom_tree)
    if not deps:
        return []
    output = []
    for line_number, (transitivity, package, version) in deps:
        output.append(
            FoundDependency(
                package=package,
                version=version,
                ecosystem=Ecosystem(Maven()),
                allowed_hashes={},
                transitivity=transitivity,
                line_number=line_number,
            )
        )
    return output


from pathlib import Path

path = Path("/Users/matthewmcquaid/test/maven_dep_tree.txt")
