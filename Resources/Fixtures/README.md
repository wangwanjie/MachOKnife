# Milestone 1 Fixtures

MachOKnife milestone 1 uses generated fixture dylibs instead of shipping external binaries in the repository.

## Generated Fixtures

Run:

```bash
bash Scripts/build_fixtures.sh
```

This produces:

- `Resources/Fixtures/generated/libFixtureDependency.dylib`
- `Resources/Fixtures/generated/libFixture.dylib`

`libFixture.dylib` is intentionally linked with:

- `LC_ID_DYLIB = @rpath/libFixture.dylib`
- one dependency on `@rpath/libFixtureDependency.dylib`
- one `LC_RPATH = @loader_path`

That makes it a stable local sample for:

- `machoe-cli info`
- `machoe-cli list-dylibs`
- basic GUI inspection

## Optional Real-World Samples

For broader manual validation you can also inspect binaries from:

- `/Users/VanJay/Documents/Career/ReverseAndJailBreak`

Those are not required for the milestone 1 verification script.
