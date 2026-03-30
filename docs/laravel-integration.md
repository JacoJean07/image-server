# Laravel Integration Guide

This guide covers integrating jaco-image-server with a Laravel application using the S3 filesystem driver.

## Requirements

- Laravel 10 or 11/12
- `league/flysystem-aws-s3-v3` package (for S3/MinIO driver)

```bash
composer require league/flysystem-aws-s3-v3
```

---

## Filesystem disks configuration

Add to `config/filesystems.php` under the `disks` array:

```php
'minio_public' => [
    'driver'                  => 's3',
    'key'                     => env('MINIO_ACCESS_KEY'),
    'secret'                  => env('MINIO_SECRET_KEY'),
    'region'                  => 'us-east-1',           // MinIO ignores region; any value works
    'bucket'                  => env('MINIO_PUBLIC_BUCKET'),
    'endpoint'                => env('MINIO_ENDPOINT'),  // http://127.0.0.1:9000
    'use_path_style_endpoint' => true,                   // required for MinIO
    'url'                     => env('MINIO_PUBLIC_URL'), // https://yourdomain.com/media/myapp-public
    'visibility'              => 'public',
],

'minio_private' => [
    'driver'                  => 's3',
    'key'                     => env('MINIO_ACCESS_KEY'),
    'secret'                  => env('MINIO_SECRET_KEY'),
    'region'                  => 'us-east-1',
    'bucket'                  => env('MINIO_PRIVATE_BUCKET'),
    'endpoint'                => env('MINIO_ENDPOINT'),
    'use_path_style_endpoint' => true,
    'visibility'              => 'private',
],
```

## Environment variables

```ini
MINIO_ACCESS_KEY=myapp_app
MINIO_SECRET_KEY=your_secret_key
MINIO_ENDPOINT=http://127.0.0.1:9000
MINIO_PUBLIC_BUCKET=myapp-public
MINIO_PRIVATE_BUCKET=myapp-private
MINIO_PUBLIC_URL=https://yourdomain.com/media/myapp-public
```

---

## Storing files

### Public file (permanent URL)

```php
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

// Store and get URL
$path = 'products/' . Str::random(40) . '.webp';
Storage::disk('minio_public')->put($path, $fileContents, 'public');

// Get public URL (served via Nginx, not direct MinIO)
$url = Storage::disk('minio_public')->url($path);
// → https://yourdomain.com/media/myapp-public/products/abc123.webp
```

### Private file (temporary signed URL)

```php
// Store
Storage::disk('minio_private')->put('invoices/INV-001.pdf', $pdfContents);

// Generate a signed URL valid for 30 minutes
$url = Storage::disk('minio_private')->temporaryUrl(
    'invoices/INV-001.pdf',
    now()->addMinutes(30)
);
// → https://yourdomain.com/media/myapp-private/invoices/INV-001.pdf?X-Amz-Signature=...
```

The signed URL goes through Nginx (`/media/myapp-private/`) which validates that `X-Amz-Signature` is present. MinIO validates the actual signature. If either check fails, the request is rejected.

---

## Image optimization before upload

For user-generated images, optimize before storing to reduce storage costs and improve load times. Using [spatie/image](https://github.com/spatie/image):

```bash
composer require spatie/image
```

```php
use Spatie\Image\Enums\Fit;
use Spatie\Image\Image;

protected function storeOptimizedImage(mixed $uploadedFile, string $prefix = 'images'): string
{
    $tmp = tempnam(sys_get_temp_dir(), 'img_') . '.webp';

    try {
        Image::load($uploadedFile->getRealPath())
            ->fit(Fit::Crop, 800, 800)   // resize to max 800×800
            ->quality(82)                // WebP quality 82 is a good balance
            ->save($tmp);

        $path = $prefix . '/' . Str::random(40) . '.webp';
        Storage::disk('minio_public')->put($path, file_get_contents($tmp), 'public');

        return $path;
    } finally {
        if (file_exists($tmp)) {
            unlink($tmp);
        }
    }
}
```

**Why this matters**: a 5MB JPEG from a mobile phone becomes a ~80–150KB WebP at 800×800 — a 95%+ reduction.

---

## Livewire file uploads

Livewire uploads files to a temporary local disk first (via `/livewire/upload-file`), then your component processes them. For this to work with large files, ensure:

**`/etc/php/8.X/fpm/php.ini`**:
```ini
upload_max_filesize = 8M
post_max_size = 16M
```

**Nginx `server{}` block** (must be at server level, not inside a location):
```nginx
client_max_body_size 10M;
```

**Livewire component**:
```php
use Livewire\WithFileUploads;

class MyComponent extends Component
{
    use WithFileUploads;

    public $photo;  // use wire:model="photo" (NOT wire:model.live)
}
```

> **Important**: Use `wire:model="photo"` on file inputs — not `wire:model.live` or `wire:model.defer`. Livewire 3 always uploads on change regardless of modifier, but `.live` can cause unexpected double-upload behavior.

---

## Multi-tenant considerations

If your app uses multiple databases and a tenant middleware that changes the default DB connection, be careful with `Rule::unique()` validation:

```php
// BAD — uses default connection (may be a tenant DB, not where users live)
Rule::unique('users')->ignore($user->id)

// GOOD — uses the model's explicit $connection property
Rule::unique(User::class)->ignore($user->id)
```

This applies to any validation rule that references a central-DB table from a context where the default connection may have been switched.

---

## Profile photo with Jetstream

If you use Jetstream and want profile photos on MinIO instead of the local `public` disk:

**`config/jetstream.php`**:
```php
'profile_photo_disk' => 'minio_public',
```

You will need to override `App\Actions\Fortify\UpdateUserProfileInformation` to use `Storage::disk('minio_public')` instead of the default `updateProfilePhoto()` method, which hardcodes the `public` disk. See the main README for the full implementation.

---

## Generating URLs

```php
// Public — permanent, served via Nginx CDN layer
Storage::disk('minio_public')->url('products/abc.webp');
// → https://yourdomain.com/media/myapp-public/products/abc.webp

// Private — temporary signed, expires in N minutes
Storage::disk('minio_private')->temporaryUrl('docs/contract.pdf', now()->addHour());
// → https://yourdomain.com/media/myapp-private/docs/contract.pdf?X-Amz-Credential=...&X-Amz-Signature=...
```

Note: `temporaryUrl()` for public disks also works but is unnecessary — just use `url()` for public objects.
