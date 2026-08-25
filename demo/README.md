# Reader demo

This demo reproduces the repository workflow on deterministic, de-identified P110-like magnetic data with separate strain labels. It does not simulate ETP or an independent remanence dataset:

- five displacement/stress stages;
- one complete bilateral MEM probe;
- 45 columns representing 15 `Z,Y,X` sensor slots;
- active sensors 1/3/4/5/6, zero slot 2, diagnostic slot 7 and `-1` sentinel slots 8–15;
- pipe entry/exit, support/head signatures and a stress-dependent central response;
- separate stress labels and grouped AI metadata.

It demonstrates data mechanics and expected API usage. It is not a substitute for real blind-pipe validation.

## Run

From the repository root:

```powershell
python -m pip install -e ".[demo]"
python demo/run_demo.py --regenerate
```

Generated runtime data are written to `demo/input` and `demo/output`, both ignored by Git. Reader-facing figures and a compact summary are written to `demo/results`.

## Expected checks

```text
source files                 5
completed scans              5
primary feature QC failures  0
validation                   PASS
direct MPa output            disabled
```
