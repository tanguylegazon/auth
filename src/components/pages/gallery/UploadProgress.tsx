import ExpandLess from 'components/icons/ExpandLess';
import ExpandMore from 'components/icons/ExpandMore';
import React, { useState } from 'react';
import { Button, Modal, ProgressBar } from 'react-bootstrap';
import { FileRejection } from 'react-dropzone';
import { FileUploadResults, UPLOAD_STAGES } from 'services/uploadService';
import styled from 'styled-components';
import { DESKTOP_APP_DOWNLOAD_URL } from 'utils/common';
import constants from 'utils/strings/constants';
import AlertBanner from './AlertBanner';

interface Props {
    fileCounter;
    uploadStage;
    now;
    closeModal;
    retryFailed;
    fileProgress: Map<string, number>;
    show;
    fileRejections: FileRejection[];
    uploadResult: Map<string, number>;
}
interface FileProgresses {
    fileName: string;
    progress: number;
}

const Content = styled.div<{
    collapsed: boolean;
    sm?: boolean;
    height?: number;
}>`
    overflow: hidden;
    height: ${(props) => (props.collapsed ? '0px' : props.height + 'px')};
    transition: height 0.2s ease-out;
    & > p {
        padding-left: 35px;
        margin: 0;
    }
`;
const FileList = styled.ul`
    padding-left: 50px;
    margin-top: 5px;
    margin-bottom: 0px;
    & > li {
        padding-left: 10px;
        margin-bottom: 10px;
        color: #ccc;
    }
`;

const SectionTitle = styled.div`
    display: flex;
    justify-content: space-between;
    padding: 0 20px;
    color: #eee;
    font-size: 20px;
    cursor: pointer;
`;

const Section = styled.div`
    margin-top: 10px;
    margin-bottom: 10px;
`;

interface ResultSectionProps {
    fileUploadResultMap: Map<FileUploadResults, string[]>;
    fileUploadResult: FileUploadResults;
    sectionTitle;
    sectionInfo?: any;
    infoHeight: number;
}
const ResultSection = (props: ResultSectionProps) => {
    const [listView, setListView] = useState(false);
    const fileList = props.fileUploadResultMap?.get(props.fileUploadResult);
    if (!fileList?.length) {
        return <></>;
    }
    return (
        <Section>
            <SectionTitle onClick={() => setListView(!listView)}>
                {' '}
                {props.sectionTitle}{' '}
                {listView ? <ExpandLess /> : <ExpandMore />}
            </SectionTitle>
            <Content
                collapsed={!listView}
                height={fileList.length * 33 + 5 + props.infoHeight}>
                {props.sectionInfo && <p>{props.sectionInfo}</p>}
                <FileList>
                    {fileList.map((fileName) => (
                        <li key={fileName}>{fileName}</li>
                    ))}
                </FileList>
            </Content>
        </Section>
    );
};

interface InProgressProps {
    sectionTitle: string;
    fileProgressStatuses: FileProgresses[];
}
const InProgressSection = (props: InProgressProps) => {
    const [listView, setListView] = useState(true);
    const fileList = props.fileProgressStatuses;
    if (!fileList?.length) {
        return <></>;
    }
    if (!fileList?.length) {
        return <></>;
    }
    return (
        <Section>
            <SectionTitle onClick={() => setListView(!listView)}>
                {' '}
                {props.sectionTitle}{' '}
                {listView ? <ExpandLess /> : <ExpandMore />}
            </SectionTitle>
            <Content collapsed={!listView} height={fileList.length * 35}>
                <FileList>
                    {fileList.map(({ fileName, progress }) => (
                        <li key={fileName}>
                            {constants.FILE_UPLOAD_PROGRESS(fileName, progress)}
                        </li>
                    ))}
                </FileList>
            </Content>
        </Section>
    );
};

const NotUploadSectionHeader = () => (
    <AlertBanner variant="warning" style={{ marginTop: '30px' }}>
        {constants.FILE_NOT_UPLOADED_LIST}
    </AlertBanner>
);

export default function UploadProgress(props: Props) {
    const fileProgressStatuses = [] as FileProgresses[];
    const fileUploadResultMap = new Map<FileUploadResults, string[]>();
    let filesNotUploaded = false;

    if (props.fileProgress) {
        for (const [fileName, progress] of props.fileProgress) {
            fileProgressStatuses.push({ fileName, progress });
        }
    }
    if (props.uploadResult) {
        for (const [fileName, progress] of props.uploadResult) {
            if (!fileUploadResultMap.has(progress)) {
                fileUploadResultMap.set(progress, []);
            }
            if (progress < 0) {
                filesNotUploaded = true;
            }
            const fileList = fileUploadResultMap.get(progress);
            fileUploadResultMap.set(progress, [...fileList, fileName]);
        }
    }

    return (
        <Modal
            show={props.show}
            onHide={
                props.uploadStage !== UPLOAD_STAGES.FINISH
                    ? () => null
                    : props.closeModal
            }
            aria-labelledby="contained-modal-title-vcenter"
            centered
            backdrop={fileProgressStatuses?.length !== 0 ? 'static' : 'true'}>
            <Modal.Header
                style={{
                    display: 'flex',
                    justifyContent: 'center',
                    textAlign: 'center',
                    borderBottom: 'none',
                    paddingTop: '30px',
                    paddingBottom: '0px',
                }}
                closeButton={props.uploadStage === UPLOAD_STAGES.FINISH}>
                <h4 style={{ width: '100%' }}>
                    {props.uploadStage === UPLOAD_STAGES.UPLOADING
                        ? constants.UPLOAD[props.uploadStage](props.fileCounter)
                        : constants.UPLOAD[props.uploadStage]}
                </h4>
            </Modal.Header>
            <Modal.Body>
                {(props.uploadStage ===
                    UPLOAD_STAGES.READING_GOOGLE_METADATA_FILES ||
                    props.uploadStage === UPLOAD_STAGES.UPLOADING) && (
                    <ProgressBar
                        now={props.now}
                        animated
                        variant="upload-progress-bar"
                    />
                )}
                <InProgressSection
                    fileProgressStatuses={fileProgressStatuses}
                    sectionTitle={constants.INPROGRESS_UPLOADS}
                />

                <ResultSection
                    fileUploadResultMap={fileUploadResultMap}
                    fileUploadResult={FileUploadResults.UPLOADED}
                    sectionTitle={constants.SUCCESSFUL_UPLOADS}
                    infoHeight={0}
                />

                {props.uploadStage === UPLOAD_STAGES.FINISH &&
                    filesNotUploaded && <NotUploadSectionHeader />}
                <ResultSection
                    fileUploadResultMap={fileUploadResultMap}
                    fileUploadResult={FileUploadResults.BLOCKED}
                    sectionTitle={constants.BLOCKED_UPLOADS}
                    sectionInfo={constants.ETAGS_BLOCKED(
                        DESKTOP_APP_DOWNLOAD_URL
                    )}
                    infoHeight={140}
                />
                <ResultSection
                    fileUploadResultMap={fileUploadResultMap}
                    fileUploadResult={FileUploadResults.FAILED}
                    sectionTitle={constants.FAILED_UPLOADS}
                    sectionInfo={constants.FAILED_INFO}
                    infoHeight={48}
                />
                <ResultSection
                    fileUploadResultMap={fileUploadResultMap}
                    fileUploadResult={FileUploadResults.SKIPPED}
                    sectionTitle={constants.SKIPPED_FILES}
                    sectionInfo={constants.SKIPPED_INFO}
                    infoHeight={32}
                />
                <ResultSection
                    fileUploadResultMap={fileUploadResultMap}
                    fileUploadResult={FileUploadResults.UNSUPPORTED}
                    sectionTitle={constants.UNSUPPORTED_FILES}
                    sectionInfo={constants.UNSUPPORTED_INFO}
                    infoHeight={32}
                />

                {props.uploadStage === UPLOAD_STAGES.FINISH && (
                    <Modal.Footer style={{ border: 'none' }}>
                        {props.uploadStage === UPLOAD_STAGES.FINISH &&
                            (fileUploadResultMap?.get(FileUploadResults.FAILED)
                                ?.length > 0 ||
                            fileUploadResultMap?.get(FileUploadResults.BLOCKED)
                                ?.length > 0 ? (
                                <Button
                                    variant="outline-success"
                                    style={{ width: '100%' }}
                                    onClick={props.retryFailed}>
                                    {constants.RETRY_FAILED}
                                </Button>
                            ) : (
                                <Button
                                    variant="outline-secondary"
                                    style={{ width: '100%' }}
                                    onClick={props.closeModal}>
                                    {constants.CLOSE}
                                </Button>
                            ))}
                    </Modal.Footer>
                )}
            </Modal.Body>
        </Modal>
    );
}
