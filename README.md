# Achterhus Server Tools

## Configuration -- the `.env.json` File

### General Considerations

The file type is regular JSON.

Specific services/applications require certain configuration key/values pairs.

However, there is a degree of freedom when creating these key/value entries.

For example, any absolute path can simply be written like `"photo-storage": "/path/to/storage/photos"`. However, it is also possible to specify `photo-storage` as a path relative to a base path (which ultimately needs to be an abolute one).

```json
{
    "storage-dir": "/path/to/storage",
    "photo-storage": {
        "type": "relative-path",
        "name": "photos",
        "base-path": "{storage-dir}"
    }
}
```

There is a special placeholder `{HOME}` -- representing the user's home directory -- that can be used as the base path in relative path definitions.

The `Configuration` class will be trying to resolve these recursive/nested paths until the value either represents a simple string or a referenced key cannot be found. In the latter case, an exception will be thrown.

### Configuration Keys

| Key | Type | Service | Description |
| --- | --- | --- | --- |
| `version` | `number` | | Required. Must be value `2`. Otherwise, the schema will not be recognised. |
| `service-base-dir` | `Path` | | Required. Represents the directory where any service can store their data. |
| `photo-inbox` | `Path` | `photo-processor` | Represents the directory in which photos will be discovered. Photos will be moved to `{photo-storage}/<year>` where `<year>` represents the year the photo was taken. |
| `photo-storage` | `Path` | `photo-processor` | Represents the base directory in which photos will be stored. The photo processor will create sub-directories representing the year the photo was taken. |
| `podcast-storage` | `Path` | `download-podcasts` | Represents the base directory in which podcasts will be stored. |
