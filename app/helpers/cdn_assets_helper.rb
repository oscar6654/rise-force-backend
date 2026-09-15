# Serve Active Storage blobs/variants through CloudFront when configured,
# falling back to standard Active Storage URLs otherwise. Mirrors the
# vcsi-repairs pattern: stable, UNSIGNED CDN URLs built from the S3 key
# (https://<host>/<key>) so browsers and the CloudFront edge cache them,
# instead of re-downloading rotating presigned URLs from S3 (the cost driver).
module CdnAssetsHelper
  # Normalised CloudFront host (no scheme, no trailing slash), or "" when unset.
  def cdn_host
    SystemSetting.get("cloudfront_host", "").to_s.sub(%r{\Ahttps?://}i, "").chomp("/")
  end

  def cdn_thumbnails_enabled?
    SystemSetting.get("cloudfront_thumbnails", false).to_s.in?(%w[true 1 yes])
  end

  # Full-size blob URL.
  def cdn_url(attachment)
    return nil unless attachment&.attached?

    host = cdn_host
    host.present? ? "https://#{host}/#{attachment.blob.key}" : url_for(attachment)
  end

  # Resized variant URL. Only pointed at CloudFront when the thumbnails flag is
  # on (the variant must already exist in S3, else it 404s). Variant keys are
  # deterministic because track_variants is left off.
  def cdn_variant_url(attachment, resize_to_limit:)
    return nil unless attachment&.attached?

    variant = attachment.variant(resize_to_limit: resize_to_limit)
    host = cdn_host
    if host.present? && cdn_thumbnails_enabled?
      "https://#{host}/#{variant.key}"
    else
      url_for(variant)
    end
  end
end
