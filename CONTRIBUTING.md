# Contributing

1. Never commit raw customer or field data, local absolute paths, credentials or blind labels.
2. Add a manifest/config fixture and a regression test for every new sensor adapter.
3. Bump the relevant standardizer/feature version when output semantics change.
4. Preserve raw values; cleaning produces a new column or layer.
5. Keep label-dependent ROI selection outside blind inference code.
6. Split model evaluation by pipe and physical run, never by rows or windows.
7. A pull request that changes schema, QC gates or feature formulas must document migration and backward compatibility.

