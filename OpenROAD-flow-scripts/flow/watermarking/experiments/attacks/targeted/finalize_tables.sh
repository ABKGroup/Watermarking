#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
# Re-aggregate targeted results and print paper-ready tab:targeted_attack rows.
# Run after the routing reroute sweep (run_targeted_attack.py --stages routing)
# finishes, to refresh the Routing (T_R) rows of tab:targeted_attack.
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../../../wm_env.sh"
cd "${HERE}/../.."
PY_BIN="$(wm_python)"
"${PY_BIN}" aggregate.py --what targeted
"${PY_BIN}" render_tex.py
echo "=== paper-ready tab:targeted_attack rows (placement r_P / cts r_C / routing T_R) ==="
python3 - <<'PY'
import csv
rows=list(csv.DictReader(open('results/phase3/targeted.csv')))
by={(r['platform'],r['design'],r['stage'],r['q_s']):r for r in rows}
order=[('nangate45','jpeg','JPEG (NG45)'),('nangate45','swerv_wrapper','SweRV (NG45)'),
       ('nangate45','ariane136','Ariane (NG45)'),('nangate45','bp_multi_top','BP (NG45)'),
       ('asap7','jpeg','JPEG (ASAP7)'),('asap7','swerv_wrapper','SweRV (ASAP7)'),
       ('asap7','ariane','Ariane (ASAP7)'),('asap7','cva6','CVA6 (ASAP7)')]
qs=['0.1','0.2','0.5','0.8','1.0']
for stage,col,fmt in [('placement','r_P','%.3f'),('cts','r_C','%.3f'),('routing','T_R','%.2f')]:
    print('--',stage,'--')
    for p,d,lab in order:
        if stage=='routing' and p=='asap7': continue
        cs=[]
        for q in qs:
            v=by.get((p,d,stage,q),{}).get(col,'')
            cs.append((fmt%float(v)) if v not in('',None) else '--')
        print('  & %-15s & %s \\\\'%(lab,' & '.join(cs)))
PY
