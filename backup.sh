#! /bin/sh

set -e
set -o pipefail

if [ "${S3_ACCESS_KEY_ID}" = "**None**" ]; then
  echo "You need to set the S3_ACCESS_KEY_ID environment variable."
  exit 1
fi

if [ "${S3_SECRET_ACCESS_KEY}" = "**None**" ]; then
  echo "You need to set the S3_SECRET_ACCESS_KEY environment variable."
  exit 1
fi

if [ "${S3_BUCKET}" = "**None**" ]; then
  echo "You need to set the S3_BUCKET environment variable."
  exit 1
fi

if [ "${POSTGRES_DATABASE}" = "**None**" ]; then
  echo "You need to set the POSTGRES_DATABASE environment variable."
  exit 1
fi

if [ "${POSTGRES_HOST}" = "**None**" ]; then
  if [ -n "${POSTGRES_PORT_5432_TCP_ADDR}" ]; then
    POSTGRES_HOST=$POSTGRES_PORT_5432_TCP_ADDR
    POSTGRES_PORT=$POSTGRES_PORT_5432_TCP_PORT
  else
    echo "You need to set the POSTGRES_HOST environment variable."
    exit 1
  fi
fi

if [ "${POSTGRES_USER}" = "**None**" ]; then
  echo "You need to set the POSTGRES_USER environment variable."
  exit 1
fi

if [ "${POSTGRES_PASSWORD}" = "**None**" ]; then
  echo "You need to set the POSTGRES_PASSWORD environment variable or link to a container named POSTGRES."
  exit 1
fi

if [ "${S3_ENDPOINT}" == "**None**" ]; then
  AWS_ARGS=""
else
  AWS_ARGS="--endpoint-url ${S3_ENDPOINT}"
fi

# env vars needed for aws tools
export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$S3_REGION

# AWS Lambda sets these and it messes up the push to S3
unset AWS_SECURITY_TOKEN
unset AWS_SESSION_TOKEN

# env vars needed for pgdump
export PGPASSWORD=$POSTGRES_PASSWORD
POSTGRES_HOST_OPTS="-h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER $POSTGRES_EXTRA_OPTS"

echo "Creating dump of ${POSTGRES_DATABASE} database from ${POSTGRES_HOST} and uploading dump to ${S3_BUCKET}..."


psql $POSTGRES_HOST_OPTS -d $POSTGRES_DATABASE -w -c "COPY (WITH t2 AS (select row_to_json(t) as js from cans.i_18_n t), t1 AS (SELECT ARRAY_TO_JSON(array_agg(js)) as \"i_18_n\" FROM t2) SELECT row_to_json(t1) FROM t1) TO STDOUT WITH ENCODING 'UTF-8'" | sed 's/\\\\/\\/g' | aws $AWS_ARGS s3 cp - s3://$S3_BUCKET/$S3_PREFIX/row_i_18_n_$(date +"%Y-%m-%d").json && echo "Dump of row_i_18_n_$(date +"%Y-%m-%d").json done" || exit 2 &

psql $POSTGRES_HOST_OPTS -d $POSTGRES_DATABASE -w -c "COPY (WITH t2 AS (select row_to_json(t) as js from cans.instrument t), t1 AS (SELECT ARRAY_TO_JSON(array_agg(js)) as \"instrument\" FROM t2) SELECT row_to_json(t1) from t1) TO STDOUT WITH ENCODING 'UTF-8'" | sed 's/\\\\/\\/g' | aws $AWS_ARGS s3 cp - s3://$S3_BUCKET/$S3_PREFIX/row_instrument_$(date +"%Y-%m-%d").json && echo "Dump of row_instrument_$(date +"%Y-%m-%d").json done" || exit 2 &

psql $POSTGRES_HOST_OPTS -d $POSTGRES_DATABASE -w -c "COPY (WITH t2 AS (select row_to_json(t) as js from cans_report.person_v t), t1 AS (SELECT ARRAY_TO_JSON(array_agg(js)) as \"person_v\" FROM t2) SELECT row_to_json(t1) FROM t1) TO STDOUT WITH ENCODING 'UTF-8'" | sed 's/\\\\/\\/g' | aws $AWS_ARGS s3 cp - s3://$S3_BUCKET/$S3_PREFIX/row_person_$(date +"%Y-%m-%d").json && echo "Dump of row_person_$(date +"%Y-%m-%d").json done" || exit 2 &

psql $POSTGRES_HOST_OPTS -d $POSTGRES_DATABASE -w -c "COPY (WITH t2 AS (select row_to_json(t) as js from cans_report.assessment_domain_v t), t1 AS (SELECT ARRAY_TO_JSON(array_agg(js)) as \"assessment_domain_v\" FROM t2) SELECT row_to_json(t1) from t1) TO STDOUT WITH ENCODING 'UTF-8'" | sed 's/\\\\/\\/g' | aws $AWS_ARGS s3 cp - s3://$S3_BUCKET/$S3_PREFIX/row_domain_$(date +"%Y-%m-%d").json && echo "Dump of row_domain_$(date +"%Y-%m-%d").json done" || exit 2 &

#psql $POSTGRES_HOST_OPTS -d $POSTGRES_DATABASE -w -c "COPY (WITH t2 AS (select row_to_json(t) as js from cans_report.assessment_item_v t), t1 AS (SELECT ARRAY_TO_JSON(array_agg(js)) as \"assessment_item_v\" FROM t2) SELECT row_to_json(t1) FROM t1) TO STDOUT WITH ENCODING 'UTF-8'" | sed 's/\\\\/\\/g' | aws $AWS_ARGS s3 cp - s3://$S3_BUCKET/$S3_PREFIX/row_item_$(date +"%Y-%m-%d").json || exit 2

psql $POSTGRES_HOST_OPTS -d $POSTGRES_DATABASE -w -c "COPY (WITH t2 AS (select row_to_json(t) as js from cans_report.assessment_item_v t where mod(assessment_id,2) = 1), t1 AS (SELECT ARRAY_TO_JSON(array_agg(js)) as "assessment_item_v" FROM t2) SELECT row_to_json(t1) FROM t1) TO STDOUT WITH ENCODING 'UTF-8';" | sed 's/\\\\/\\/g' | aws $AWS_ARGS s3 cp - s3://$S3_BUCKET/$S3_PREFIX/row_item_part1_$(date +"%Y-%m-%d").json || exit 2
echo "Dump of row_item_part1_$(date +"%Y-%m-%d").json done"

psql $POSTGRES_HOST_OPTS -d $POSTGRES_DATABASE -w -c "COPY (WITH t2 AS (select row_to_json(t) as js from cans_report.assessment_item_v t where mod(assessment_id,2) = 0), t1 AS (SELECT ARRAY_TO_JSON(array_agg(js)) as "assessment_item_v" FROM t2) SELECT row_to_json(t1) FROM t1) TO STDOUT WITH ENCODING 'UTF-8';" | sed 's/\\\\/\\/g' | aws $AWS_ARGS s3 cp - s3://$S3_BUCKET/$S3_PREFIX/row_item_part2_$(date +"%Y-%m-%d").json || exit 2
echo "Dump of row_item_part2_$(date +"%Y-%m-%d").json done"

echo "$(aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$S3_PREFIX/row_item_part2_$(date +"%Y-%m-%d").json -) $(aws $AWS_ARGS s3 cp s3://$S3_BUCKET/$S3_PREFIX/row_item_part1_$(date +"%Y-%m-%d").json -)" | /usr/bin/jq -s '.[0].assessment_item_v + .[1].assessment_item_v | {assessment_item_v: .}' | aws $AWS_ARGS s3 cp - s3://$S3_BUCKET/$S3_PREFIX/row_item_$(date +"%Y-%m-%d").json || exit 2
echo "Dump of row_item_$(date +"%Y-%m-%d").json done"

psql $POSTGRES_HOST_OPTS -d $POSTGRES_DATABASE -w -c "COPY (WITH t2 AS (select row_to_json(t) as js from cans_report.assessment_v t), t1 AS (SELECT ARRAY_TO_JSON(array_agg(js)) as \"assessment_v\" FROM t2) SELECT row_to_json(t1) FROM t1) TO STDOUT WITH ENCODING 'UTF-8'" | sed 's/\\\\/\\/g' | aws $AWS_ARGS s3 cp - s3://$S3_BUCKET/$S3_PREFIX/row_assessment_$(date +"%Y-%m-%d").json || exit 2
echo "Dump of row_assessment_$(date +"%Y-%m-%d").json done"

#pg_dump $POSTGRES_HOST_OPTS $POSTGRES_DATABASE | gzip | aws $AWS_ARGS s3 cp - s3://$S3_BUCKET/$S3_PREFIX/${POSTGRES_DATABASE}_$(date +"%Y-%m-%dT%H:%M:%SZ").sql.gz || exit 2

echo "SQL backup uploaded successfully"
