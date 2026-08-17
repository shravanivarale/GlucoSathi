# Failure Cases

Every failure is returned with the standard error envelope and a stable, machine-readable `code`:

```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "FOOD_NOT_RECOGNIZED",
    "message": "We couldn't identify the food in this image."
  }
}
```

| Code                  | HTTP | Meaning                                                             |
|-----------------------|------|----------------------------------------------------------------------|
| `INVALID_IMAGE`       | 400  | No image provided, or the image is corrupt/unreadable/unsupported format. |
| `IMAGE_TOO_LARGE`     | 413  | The image exceeds the maximum allowed size.                         |
| `FOOD_NOT_RECOGNIZED` | 422  | The image contains no food, or the food could not be identified.    |
| `LOW_CONFIDENCE`      | 422  | Food identified but recognition confidence is below the threshold.  |
| `FOOD_NOT_FOUND`      | 404  | The recognized food has no matching entry in the nutrition database. |
| `NUTRITION_DATA_NOT_FOUND` | 404 | The food exists but its nutrition values are unavailable.        |
| `ANALYSIS_FAILED`     | 502  | The recognition service failed to produce a result.                 |
| `INTERNAL_ERROR`      | 500  | Unexpected backend error.                                           |

## Client behavior

Flutter maps these codes to sealed subtypes in `lib/core/errors/app_failure.dart`:

| Code                      | Dart failure type                |
|---------------------------|----------------------------------|
| `INVALID_IMAGE`           | `ImageInvalidFailure`            |
| `IMAGE_TOO_LARGE`         | `ImageTooLargeFailure`           |
| `FOOD_NOT_RECOGNIZED`     | `FoodNotRecognizedFailure`       |
| `LOW_CONFIDENCE`          | `LowConfidenceFailure`           |
| `FOOD_NOT_FOUND`          | `FoodNotFoundFailure`            |
| `NUTRITION_DATA_NOT_FOUND`| `NutritionDataNotFoundFailure`   |
| `ANALYSIS_FAILED`         | `AnalysisFailedFailure`          |
| `INTERNAL_ERROR`          | `InternalErrorFailure`           |
| (any other)               | `UnknownFailure`                 |