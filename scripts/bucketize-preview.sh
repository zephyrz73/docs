#!/bin/bash

# Exit on any non-zero status or unbound variable, and print all commands to the terminal.
set -euo pipefail

source ./scripts/common.sh

# This script takes the built Hugo site and:
#   * creates a new S3 bucket named with the current Git SHA and a timestamp (of now)
#   * pushes the content of the website into the new S3 bucket
#   * tests the built website with a headless browser to ensure pages are rendering and
#     behaving properly

# The docroot of the built website.
build_dir="public"

# The S3 bucket to publish to.
gh_pr_number=$(cat "$GITHUB_EVENT_PATH" | jq -r ".number")
destination_bucket=$(echo "pulumi-docs-preview-${gh_pr_number}")
destination_bucket_uri="s3://${destination_bucket}"

# Read the region from the stack's config -- we use it below.
aws_region="us-west-2"

# Push site content to the bucket.
echo "Synchronizing to $destination_bucket_uri..."
aws s3 mb $destination_bucket_uri --region $aws_region
aws s3 website $destination_bucket_uri --index-document index.html --error-document 404.html
aws s3 sync "$build_dir" "$destination_bucket_uri" --acl public-read

echo "Sync complete."
s3_website_url="http://${destination_bucket}.s3-website.${aws_region}.amazonaws.com"
echo "$s3_website_url"

# Set the content-type of latest-version explicitly. (Otherwise, it'll be set as binary/octet-stream.)
aws s3 cp "$build_dir/latest-version" "${destination_bucket_uri}/latest-version" \
    --content-type "text/plain" --acl public-read --metadata-directive REPLACE

echo "Done! The bucket website is now built and available at ${s3_website_url}."

# Smoke test the deployed website. Specs are in ../cypress/integration.
echo "Running tests..."
CYPRESS_BASE_URL="$s3_website_url" yarn run cypress run --headless

# At this point, we have a bucket that's suitable for deployment. As a result of this run,
# we leave a file in the project root indicating the name of the bucket that was generated
# and the associated commit SHA, and then we upload that file into the bucket as well, for
# reference. The Pulumi program will expect this file to exist, and will use the bucket
# name to set the CloudFront origin on the next Pulumi run.
#
# Why use a local file and not `pulumi config`, or some other persistence store? Because
# we need ensure that every CI job deploys only what it was responsible for building. If
# we wrote to an async store in this step, and read from that store in the follow-on
# Pulumi job, it'd be easy for anothe Pulumi run to pick up and deploy this job's
# artifact, or vice-versa. Coupled with the locking we get from the Pulumi Service, using
# a local file is the safest way to ensure we're always deploying what we think we are.
echo "Writing result metadata."
metadata='{
    "bucket": "%s",
    "commit": "%s"
}'
printf "$metadata" "$destination_bucket" "$git_sha" > "$metadata_file"

# Copy the file to the destination bucket, for future reference.
aws s3 cp "$metadata_file" "${destination_bucket_uri}/metadata.json" --region $aws_region --acl public-read

# Next, post a comment to the PR that directs the user to the resulting bucket URL.
PR_COMMENT_API_LINK=$(cat "$GITHUB_EVENT_PATH" | jq -r ".pull_request._links.comments.href")
curl -X POST -H "Authorization: token $GITHUB_TOKEN" \
    -d "{ \"body\": \"Preview at ${s3_website_url}.\" }" \
    $PR_COMMENT_API_LINK
